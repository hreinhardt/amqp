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
    

    --subscribe to the queues
    _ <- consumeMsgs chan "myQueueDE" Ack myCallbackDE
    _ <- consumeMsgs chan "myQueueEN" Ack myCallbackEN
    
    
    _ <- getLine -- wait for keypress
    closeConnection conn
    putStrLn "connection closed"

    
    

myCallbackDE :: (Message,Envelope) -> IO ()
myCallbackDE (msg, env) = do
    putStrLn $ "received from DE: "++(BL.unpack $ msgBody msg)
    ackEnv env


myCallbackEN :: (Message,Envelope) -> IO ()
myCallbackEN (msg, env) = do
    putStrLn $ "received from EN: "++(BL.unpack $ msgBody msg)
    ackEnv env
