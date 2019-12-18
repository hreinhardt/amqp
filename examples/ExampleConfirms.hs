{-# OPTIONS -XOverloadedStrings #-}
module ExampleConfirms where

import Network.AMQP
import Control.Monad(forM_,forever)
import Control.Concurrent(forkIO,threadDelay)
import Control.Concurrent.Chan
import Control.Concurrent.STM
import Data.Time.Clock
import Data.IntSet
import qualified Data.ByteString.Lazy.Char8 as BL

showResult :: ConfirmationResult -> IO ()
showResult (Partial (a, n, p)) = putStrLn $ "Acks: "++(show . size $ a)++" Nacks: "++(show . size $ n)++" pending: "++(show . size $ p)
showResult (Complete (a, n)) = putStrLn $ "Acks: "++(show . size $ a)++" Nacks: "++(show . size $ n)
main = do
    conn <- openConnection "localhost" "/" "guest" "guest"
    chan <- openChannel conn

    confirmSelect chan False

    --declare queues and bindings
    declareQueue chan newQueue {queueName = "myQueue", queueAutoDelete = True}
    bindQueue chan "myQueue" "amq.topic" "conf.*"

    --activate a consumer so that messages won't be returned
    consumeMsgs chan "myQueue" Ack (\(msg,env) -> ackEnv env)

    forkIO $ forever $ do
      putStrLn "Publishing messages.."
      forM_ [1..100] (\i -> publishMsg chan
                            "amq.topic"
                            "conf.hello"
                            (newMsg {msgBody = (BL.pack "hallo welt"), msgDeliveryMode = Just NonPersistent})
                     )
      putStr "Waiting for confirms..."
      showResult =<< waitForConfirms chan -- or waitForConfirmsUntil chan (10^6)
      threadDelay (10^6)

    getLine
    closeConnection conn
