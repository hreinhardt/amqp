module Network.AMQP.Protocol where


import Data.Binary
import Data.Binary.Get
import Data.Binary.Put

import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Binary.Put as BPut
import Control.Monad

import Data.Char
import Data.Int

import Network.AMQP.Types
import Network.AMQP.Generated


--True if a content (contentheader and possibly contentbody) will follow the method        
hasContent (MethodPayload (Basic_get_ok _ _ _ _ _)) = True
hasContent (MethodPayload (Basic_deliver _ _ _ _ _)) = True
hasContent (MethodPayload (Basic_return _ _ _ _)) = True
hasContent _ = False
        

data Frame = Frame ChannelID FramePayload --channel, payload
    deriving Show
instance Binary Frame where
    get = do
        frameType <- getWord8
        channel <- get :: Get ChannelID
        payloadSize <- get :: Get PayloadSize 
        payload <- getPayload frameType payloadSize :: Get FramePayload
        0xCE <- getWord8 --frame end
        return $ Frame channel payload  
    put (Frame chan payload) = do
        putWord8 $ frameType payload
        put chan
        let buf = runPut $ putPayload payload
        put ((fromIntegral $ BL.length buf)::PayloadSize)
        putLazyByteString buf
        putWord8 0xCE

        
-- gets the size of the frame
-- the bytestring should be at least 7 bytes long, otherwise this method will fail
peekFrameSize :: BL.ByteString -> PayloadSize        
peekFrameSize b = runGet f b
  where
    f = do
        getWord8 -- 1 byte
        get :: Get ChannelID -- 2 bytes
        ps <- get :: Get PayloadSize -- 4 bytes
        return ps
    

data FramePayload = 
               MethodPayload MethodPayload 
             | ContentHeaderPayload ShortInt ShortInt LongLongInt ContentHeaderProperties --classID, weight, bodySize, propertyFields
             | ContentBodyPayload BL.ByteString
    deriving Show
    
frameType (MethodPayload _) = 1    
frameType (ContentHeaderPayload _ _ _ _) = 2
frameType (ContentBodyPayload _) = 3
    
getPayload 1 payloadSize = do --METHOD FRAME
    payLoad <- get :: Get MethodPayload
    return (MethodPayload payLoad)
    
getPayload 2 payloadSize = do --content header frame
    classID <- get :: Get ShortInt
    weight <- get :: Get ShortInt
    bodySize <- get :: Get LongLongInt
   
    props <- getContentHeaderProperties classID
    return (ContentHeaderPayload classID weight bodySize props)

getPayload 3 payloadSize = do --content body frame
    payload <- getLazyByteString $ fromIntegral payloadSize
    return (ContentBodyPayload payload)
    
putPayload (MethodPayload payload) = do
    put payload
      
putPayload (ContentHeaderPayload classID weight bodySize p) = do
    put classID
    put weight
    put bodySize
    
    putContentHeaderProperties p
    
putPayload (ContentBodyPayload payload) = do
    putLazyByteString payload    
        



