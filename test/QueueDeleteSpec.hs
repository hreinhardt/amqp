{-# OPTIONS -XOverloadedStrings #-}

module QueueDeleteSpec (main, spec) where

import Test.Hspec
import Network.AMQP

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "deleteQueue" $ do
      context "when queue exists" $ do
          it "deletes the queue" $ do
              conn <- openConnection "127.0.0.1" "/" "guest" "guest"
              ch   <- openChannel conn

              (q, _, _) <- declareQueue ch (newQueue {queueName      = "haskell-amqp.queues.to-be-deleted",
                                                      queueExclusive = True})


              n <- deleteQueue ch q
              n `shouldBe` 0

              let ex = (ChannelClosedException "NOT_FOUND - no queue 'haskell-amqp.queues.to-be-deleted' in vhost '/'")
              (declareQueue ch $ newQueue {queueName = q, queuePassive = True}) `shouldThrow` (== ex)

              closeConnection conn

          context "when queue DOES NOT exist" $ do
              it "throws an exception" $ do
                  conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                  ch   <- openChannel conn

                  let q  = "haskell-amqp.queues.GmN8rozyXiz2mQYcFrQg"
                      ex = (ChannelClosedException "NOT_FOUND - no queue 'haskell-amqp.queues.GmN8rozyXiz2mQYcFrQg' in vhost '/'")
                  (declareQueue ch $ newQueue {queueName = q, queuePassive = True}) `shouldThrow` (== ex)

                  closeConnection conn
