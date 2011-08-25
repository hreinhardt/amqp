{-# OPTIONS -XBangPatterns #-}
module Network.AMQP.Types
    (Octet,
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
     )
     where


import Data.Int
import Data.Char
import Data.Binary
import Data.Binary.Get
import Data.Binary.Put
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.ByteString.Lazy.Internal as BL
import qualified Data.Binary.Put as BPut
import Control.Monad
import qualified Data.Map as M



-- performs runGet on a bytestring until the string is empty
readMany :: (Show t, Binary t) => BL.ByteString -> [t]
readMany str = runGet (readMany' [] 0) str
readMany' _ 1000 = error "readMany overflow"
readMany' acc overflow = do
    x <- get
    rem <- remaining
    if rem > 0 
        then readMany' (x:acc) (overflow+1)
        else return (x:acc)
        
putMany x = mapM_ put x

-- Lowlevel Types
type Octet = Word8
type Bit = Bool

type ChannelID = ShortInt
type PayloadSize = LongInt

type ShortInt = Word16
type LongInt = Word32
type LongLongInt = Word64



newtype ShortString = ShortString String
    deriving (Show, Ord, Eq)
instance Binary ShortString where
    get = do
      len <- getWord8
      dat <- getByteString (fromIntegral len)
      return $ ShortString $ BS.unpack dat
    put (ShortString x) = do
        let s = BS.pack $ take 255 x --ensure string isn't longer than 255 bytes
        putWord8 $ fromIntegral (BS.length s)
        putByteString s
    
newtype LongString = LongString String
    deriving Show
instance Binary LongString where
    get = do
      len <- getWord32be
      dat <- getByteString (fromIntegral len)
      return $ LongString $ BS.unpack dat
    put (LongString x) = do
        putWord32be $ fromIntegral (length x)
        putByteString (BS.pack x) 

type Timestamp = LongLongInt



--- field-table ---
data FieldTable = FieldTable (M.Map ShortString FieldValue)
    deriving Show
instance Binary FieldTable where
    get = do
        len <- get :: Get LongInt --length of fieldValuePairs in bytes
        
        if len > 0 
            then do
                fvp <- getLazyByteString (fromIntegral len)
                let !fields = readMany fvp
                
                return $ FieldTable $ M.fromList fields
            else return $ FieldTable $ M.empty
                
    put (FieldTable fvp) = do
        let bytes = runPut (putMany $ M.toList fvp) :: BL.ByteString
        put ((fromIntegral $ BL.length bytes):: LongInt)
        putLazyByteString bytes
    

    
--- field-value ---  

data FieldValue = FVLongString LongString
                | FVSignedInt Int32
                | FVDecimalValue DecimalValue
                | FVTimestamp Timestamp
                | FVFieldTable FieldTable
    deriving Show
                
instance Binary FieldValue where
    get = do
        fieldType <- getWord8
        case chr $ fromIntegral fieldType of
            'S' -> do 
                x <- get :: Get LongString
                return $ FVLongString x
            'I' -> do
                x <- get :: Get Int32
                return $ FVSignedInt x
            'D' -> do
                x <- get :: Get DecimalValue
                return $ FVDecimalValue $ x
            'T' -> do
                x <- get :: Get Timestamp
                return $ FVTimestamp x
            'F' -> do
                ft <- get :: Get FieldTable
                return $ FVFieldTable ft
    put (FVLongString s)   = put 'S' >> put s
    put (FVSignedInt s)    = put 'I' >> put s
    put (FVDecimalValue s) = put 'D' >> put s
    put (FVTimestamp s)    = put 'T' >> put s
    put (FVFieldTable s)   = put 'F' >> put s
    
    
    
data DecimalValue = DecimalValue Decimals LongInt    
    deriving Show
instance Binary DecimalValue where   
    get = do
      a <- getWord8
      b <- get :: Get LongInt
      return $ DecimalValue a b
    put (DecimalValue a b) = put a >> put b
    
type Decimals = Octet       



