module Network.AMQP.ChannelAllocator where

import qualified Data.Vector.Mutable as V
import Data.Word
import Data.Bits

newtype ChannelAllocator = ChannelAllocator (V.IOVector Word64)

newChannelAllocator :: IO ChannelAllocator
newChannelAllocator =
    fmap ChannelAllocator $ V.replicate 1024 0

allocateChannel :: ChannelAllocator -> IO Int
allocateChannel (ChannelAllocator c) = do
    maybeIx <- findFreeIndex c
    case maybeIx of
        Just chunk -> do
            word <- V.read c chunk
            let offset = findUnsetBit word
            V.write c chunk (setBit word offset)
            return (chunk*64 + offset)
        Nothing -> error "all channels are already allocated"

freeChannel :: ChannelAllocator -> Int -> IO Bool
freeChannel (ChannelAllocator c) ix = do
    let (chunk, offset) = divMod ix 64
    word <- V.read c chunk
    if testBit word offset
        then do
            V.write c chunk $ clearBit word offset
            return True
        else return False

findUnsetBit :: Word64 -> Int
findUnsetBit w = go 0
  where
    go 65 = error "findUnsetBit"
    go ix | not (testBit w ix) = ix
    go ix = go (ix+1)

findFreeIndex :: V.IOVector Word64 -> IO (Maybe Int)
findFreeIndex vec = go 0
  where
    -- TODO: make this faster
    go 1024 = return Nothing
    go ix = do
        v <- V.read vec ix
        if v /= 0xffffffffffffffff
            then return $ Just ix
            else go $! ix+1
