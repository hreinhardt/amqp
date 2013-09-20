{-# LANGUAGE BangPatterns #-}
-- |
--
-- This module contains data-types specified in the AMQP spec
module Network.AMQP.Types (
    Octet,
    Bit,
    ChannelID,
    PayloadSize,
    ShortInt,
    LongInt,
    LongLongInt,
    ShortString(..),
    LongString(..),
    Timestamp,
    FieldTable(..),
    FieldValue(..),
    Decimals,
    DecimalValue(..)
) where

import Control.Applicative
import Data.Int
import Data.Binary
import Data.Binary.Get
import Data.Binary.IEEE754
import Data.Binary.Put
import Data.Char
import Data.Text (Text)

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map as M
import qualified Data.Text.Encoding as T

-- performs runGet on a bytestring until the string is empty
readMany :: (Show a, Binary a) => BL.ByteString -> [a]
readMany = runGet (readMany' [] 0)

readMany' :: (Show a, Binary a) => [a] -> Int -> Get [a]
readMany' _ 1000 = error "readMany overflow"
readMany' acc overflow = do
    x <- get
    emp <- isEmpty
    if not emp
        then readMany' (x:acc) (overflow+1)
        else return (x:acc)

putMany :: Binary a => [a] -> PutM ()
putMany = mapM_ put

-- Lowlevel Types
type Octet = Word8
type Bit = Bool

type ChannelID = ShortInt
type PayloadSize = LongInt

type ShortInt = Word16
type LongInt = Word32
type LongLongInt = Word64

newtype ShortString = ShortString Text
    deriving (Eq, Ord, Read, Show)
instance Binary ShortString where
    get = do
      len <- getWord8
      dat <- getByteString (fromIntegral len)
      return $ ShortString $ T.decodeUtf8 dat

    put (ShortString x) = do
        let s = T.encodeUtf8 x
        if BS.length s > 255
            then error "cannot encode ShortString with length > 255"
            else do
                putWord8 $ fromIntegral (BS.length s)
                putByteString s

newtype LongString = LongString BS.ByteString
    deriving (Eq, Ord, Read, Show)
instance Binary LongString where
    get = do
      len <- getWord32be
      dat <- getByteString (fromIntegral len)
      return $ LongString dat

    put (LongString x) = do
        putWord32be $ fromIntegral (BS.length x)
        putByteString x

type Timestamp = Word64

--- field-table ---

-- | Keys must be shorter than 256 bytes when encoded as UTF-8
data FieldTable = FieldTable (M.Map Text FieldValue)
    deriving (Eq, Ord, Read, Show)
instance Binary FieldTable where
    get = do
        len <- get :: Get LongInt --length of fieldValuePairs in bytes
        if len > 0
            then do
                fvp <- getLazyByteString (fromIntegral len)
                let !fields = readMany fvp
                return $ FieldTable $ M.fromList $ map (\(ShortString a, b) -> (a,b)) fields
            else return $ FieldTable $ M.empty

    put (FieldTable fvp) = do
        let bytes = runPut (putMany $ map (\(a,b) -> (ShortString a, b)) $ M.toList fvp) :: BL.ByteString
        put ((fromIntegral $ BL.length bytes):: LongInt)
        putLazyByteString bytes

--- field-value ---

data FieldValue = FVBool Bool
                | FVInt8 Int8
                | FVInt16 Int16
                | FVInt32 Int32
                | FVInt64 Int64
                | FVFloat Float
                | FVDouble Double
                | FVDecimal DecimalValue
                | FVString Text
                | FVFieldArray [FieldValue]
                | FVTimestamp Timestamp
                | FVFieldTable FieldTable
                | FVVoid
                | FVByteArray BS.ByteString
    deriving (Eq, Ord, Read, Show)

instance Binary FieldValue where
    get = do
        fieldType <- getWord8
        case chr $ fromIntegral fieldType of
            't' -> FVBool <$> get
            'b' -> FVInt8 <$> get
            's' -> FVInt16 <$> get
            'I' -> FVInt32 <$> get
            'l' -> FVInt64 <$> get
            'f' -> FVFloat <$> getFloat32be
            'd' -> FVDouble <$> getFloat64be
            'D' -> FVDecimal <$> get
            'S' -> do
                LongString x <- get :: Get LongString
                return $ FVString $ T.decodeUtf8 x
            'A' -> do
                len <- get :: Get Int32
                if len > 0
                    then do
                        fvp <- getLazyByteString (fromIntegral len)
                        let !fields = readMany fvp
                        return $ FVFieldArray fields
                    else return $ FVFieldArray []
            'T' -> FVTimestamp <$> get
            'F' -> FVFieldTable <$> get
            'V' -> return FVVoid
            'x' -> do
                len <- get :: Get Word32
                FVByteArray <$> getByteString (fromIntegral len)
            c   -> error ("Unknown field type: " ++ show c)

    put (FVBool x) = put 't' >> put x
    put (FVInt8 x) = put 'b' >> put x
    put (FVInt16 x) = put 's' >> put x
    put (FVInt32 x) = put 'I' >> put x
    put (FVInt64 x) = put 'l' >> put x
    put (FVFloat x) = put 'f' >> putFloat32be x
    put (FVDouble x) = put 'd' >> putFloat64be x
    put (FVDecimal x) = put 'D' >> put x
    put (FVString x) = put 'S' >> put (LongString $ T.encodeUtf8 x)
    put (FVFieldArray x) = do
        put 'A'
        if length x == 0
            then put (0 :: Int32)
            else do
                let bytes = runPut (putMany x) :: BL.ByteString
                put ((fromIntegral $ BL.length bytes):: Int32)
                putLazyByteString bytes
    put (FVTimestamp s)    = put 'T' >> put s
    put (FVFieldTable s)   = put 'F' >> put s
    put (FVVoid) = put 'V'
    put (FVByteArray x) = do
        put 'x'
        let len = fromIntegral (BS.length x) :: Word32
        put len
        putByteString x

data DecimalValue = DecimalValue Decimals LongInt
    deriving (Eq, Ord, Read, Show)
instance Binary DecimalValue where
    get = do
      a <- getWord8
      b <- get :: Get LongInt
      return $ DecimalValue a b

    put (DecimalValue a b) = put a >> put b

type Decimals = Octet
