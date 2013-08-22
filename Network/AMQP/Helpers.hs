module Network.AMQP.Helpers where

import Control.Concurrent.MVar
import Control.Monad

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as BL

toStrict :: BL.ByteString -> BS.ByteString
toStrict x = BS.concat $ BL.toChunks x

toLazy :: BS.ByteString -> BL.ByteString
toLazy x = BL.fromChunks [x]

-- if the lock is open, calls to waitLock will immediately return. if it is closed, calls to waitLock will block. if the lock is killed, it will always be open and can't be closed anymore
data Lock = Lock (MVar Bool) (MVar ())

newLock :: IO Lock
newLock = do
    a <- newMVar False
    b <- newMVar ()
    return $ Lock a b

openLock :: Lock -> IO ()
openLock (Lock _ b) = void $ tryPutMVar b ()

closeLock :: Lock -> IO ()
closeLock (Lock a b) = do
    withMVar a $ \killed ->
        if killed
            then return ()
            else tryTakeMVar b >> return ()
    return ()

waitLock :: Lock -> IO ()
waitLock (Lock _ b) = readMVar b

killLock :: Lock -> IO Bool
killLock (Lock a b) = do
    modifyMVar_ a $ const (return True)
    tryPutMVar b ()