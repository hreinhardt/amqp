{-|
Module      : Main
Description : Example showing error handling

This example uses the demo ConnectionManager module to handle connection and channel errors.
You should be able to start this demo (`cabal run amqp-example-connection-management`) before
RabbitMQ is running, terminate RabbitMQ while it is running etc and it should continue to
work.

See the ConnectionManager module for an explanation of the implementation.
-}

{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module Main
    ( main
    ) where

import qualified Data.ByteString.Lazy.Char8 as BL
import           Control.Concurrent (threadDelay)
import           Control.Monad (void)
import qualified Data.Time as Dt
import           Network.AMQP ( Ack(..)
                              , DeliveryMode(..)
                              , Envelope(..)
                              , Message(..)
                              , ackEnv
                              , bindQueue
                              , consumeMsgs
                              , declareExchange
                              , declareQueue
                              , exchangeName
                              , exchangeType
                              , fromURI
                              , getServerProperties
                              , newExchange
                              , newMsg
                              , publishMsg
                              , newQueue
                              , queueName
                              )

import qualified ConnectionManager as Cm

-- | Example showing the use of ConnectionManager to manage connection and channel failure
-- You can run this example by running `make run-example-connection-management`
main :: IO ()
main = do
  -- Use `mkHandle` rather than `openConnection`
  -- This will create a "handle" that you can use to safely get the connection and a channel
  cm <- Cm.mkHandle (fromURI "amqp://guest:guest@localhost:5672") Cm.defaultOpts

  -- Example of using the connection to get the server properties
  Cm.withConnection cm $ \conn -> do
    props <- getServerProperties conn
    print props


  -----------------------------------------------------------------------------------------------------------
  -- Setup --
  --
  -- Setup for the consumer and producer
  -- Using `withChannel` to get a channel from the pool.
  --
  -- This is otherwise very similar to ExampleConsumer/ExampleProducer
  -- NB do as little work in withChannel as possible. You want to use the channel
  -- and return it to the pool so that it can be used elsewhere.
  -----------------------------------------------------------------------------------------------------------
  Cm.withChannel cm $ \chan -> do
    void $ declareQueue chan newQueue {queueName = "myQueueEN"}
    declareExchange chan newExchange {exchangeName = "topicExchg", exchangeType = "topic"}
    bindQueue chan "myQueueEN" "topicExchg" "en.*"
  -----------------------------------------------------------------------------------------------------------


  -----------------------------------------------------------------------------------------------------------
  -- Consumer --
  --
  -- If the connection is killed then any handler started by `consumeMsgs` will no longer be running.
  --
  -- The ConnectionManager has an `addOnReconnect` function that lets you run your code when a
  -- reconnect succeeds.
  -----------------------------------------------------------------------------------------------------------
  let runConsumer =
        -- The call to `consumeMsgs` that we want to keep running
        Cm.withChannel cm $ \chan -> do
         void $ consumeMsgs chan "myQueueEN" Ack myCallbackEN


  -- Start automatically of the connection is stopped
  Cm.addOnReconnect cm runConsumer
  -- And start the consumer right now as well
  runConsumer
  -----------------------------------------------------------------------------------------------------------


  -----------------------------------------------------------------------------------------------------------
  -- Producer
  --
  -- Run the producer demo loop
  -----------------------------------------------------------------------------------------------------------
  runProducer cm 0
  -----------------------------------------------------------------------------------------------------------


  -- This will never get called in this demo
  Cm.closeHandle cm



-- | Callback for the consumer
myCallbackEN :: (Message, Envelope) -> IO ()
myCallbackEN (msg, env) = do
  putStrLn $ "received from EN: " <> BL.unpack (msgBody msg)
  ackEnv env



-- | Producer loop
--
-- This loop will try to publish a message once a second
runProducer :: Cm.Handle -> Int -> IO ()
runProducer cm count = do
  dt <- Dt.getCurrentTime

  -- Do as little work in withChannel or withConnection as possible
  -- Notice that `getCurrentTime` and esp the threadDelay are called before/after withChannel
  Cm.withChannel cm $ \chan ->
    void $ publishMsg
             chan
             "topicExchg"
             "en.hello"
              (newMsg { msgBody = BL.pack (show dt <> " #" <> show count)
                      , msgDeliveryMode = Just NonPersistent
                      }
              )

  -- NB don't block in the withChannel call
  threadDelay 1_000_000
  runProducer cm (count + 1)

