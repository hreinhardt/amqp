{-# OPTIONS -XOverloadedStrings #-}
module ExampleProducer where

import Network.AMQP

import qualified Data.ByteString.Lazy.Char8 as BL


main = do
    conn <- openConnection "127.0.0.1" "/" "guest" "guest"
    chan <- openChannel conn

    
    --declare queues, exchanges and bindings
    declareQueue chan newQueue {queueName = "myQueueDE"}
    declareQueue chan newQueue {queueName = "myQueueEN"}
    
    declareExchange chan newExchange {exchangeName = "topicExchg", exchangeType = "topic"}
    bindQueue chan "myQueueDE" "topicExchg" "de.*"
    bindQueue chan "myQueueEN" "topicExchg" "en.*"
    
    --publish messages
    publishMsg chan "topicExchg" "de.hello" 
        (newMsg {msgBody = (BL.pack "hallo welt"), 
                 msgDeliveryMode = Just NonPersistent}
                )
    publishMsg chan "topicExchg" "en.hello" 
        (newMsg {msgBody = (BL.pack "hello world"), 
                 msgDeliveryMode = Just NonPersistent}
                )
                    
                
    closeConnection conn
    


    
    
