{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module Main
    ( main
    ) where

import qualified Data.ByteString.Lazy.Char8 as BL
import           Control.Concurrent (threadDelay)
import           Control.Monad (void, (>=>))
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


main :: IO ()
main = do
  cm <- Cm.mkHandle (fromURI "amqp://guest:guest@localhost:5672") Cm.defaultOpts

  Cm.withConnection cm $ getServerProperties >=> print

  Cm.withChannel cm $ \chan -> do
    void $ declareQueue chan newQueue {queueName = "myQueueEN"}
    declareExchange chan newExchange {exchangeName = "topicExchg", exchangeType = "topic"}
    bindQueue chan "myQueueEN" "topicExchg" "en.*"

  let runConsumer =
        Cm.withChannel cm $ \chan -> do
         void $ consumeMsgs chan "myQueueEN" Ack myCallbackEN


  Cm.addOnReconnect cm runConsumer
  runConsumer

  runProducer cm 0
  Cm.closeHandle cm



myCallbackEN :: (Message, Envelope) -> IO ()
myCallbackEN (msg, env) = do
  putStrLn $ "received from EN: " <> BL.unpack (msgBody msg)
  ackEnv env


runProducer :: Cm.Handle -> Int -> IO ()
runProducer cm count = do
  dt <- Dt.getCurrentTime
  -- Do as little work in withChannel or withConnection as possible
  Cm.withChannel cm $ \chan ->
    void $ publishMsg
             chan
             "topicExchg"
             "en.hello"
              (newMsg { msgBody = BL.pack (show dt <> " #" <> show count)
                      , msgDeliveryMode = Just NonPersistent
                      }
              )

  -- NB don't block in the withChannel
  threadDelay 1_000_000
  runProducer cm (count + 1)

