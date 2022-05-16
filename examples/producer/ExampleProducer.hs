{-# LANGUAGE OverloadedStrings #-}
module Main where

import Network.AMQP

import qualified Data.ByteString.Lazy.Char8 as BL


main :: IO ()
main = do
    conn <- openConnection "127.0.0.1" "/" "guest" "guest"
    chan <- openChannel conn

    
    --declare queues, exchanges and bindings
    _ <- declareQueue chan newQueue {queueName = "myQueueDE"}
    _ <- declareQueue chan newQueue {queueName = "myQueueEN"}
    
    declareExchange chan newExchange {exchangeName = "topicExchg", exchangeType = "topic"}
    bindQueue chan "myQueueDE" "topicExchg" "de.*"
    bindQueue chan "myQueueEN" "topicExchg" "en.*"
    
    --publish messages
    _ <- publishMsg chan "topicExchg" "de.hello"
        (newMsg {msgBody = (BL.pack "hallo welt"), 
                 msgDeliveryMode = Just NonPersistent}
                )
    _ <- publishMsg chan "topicExchg" "en.hello"
        (newMsg {msgBody = (BL.pack "hello world"), 
                 msgDeliveryMode = Just NonPersistent}
                )
                    
                
    closeConnection conn
    


    
    
