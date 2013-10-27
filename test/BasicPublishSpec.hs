{-# OPTIONS -XOverloadedStrings #-}

module BasicPublishSpec (main, spec) where

import Test.Hspec
import Network.AMQP

import Data.ByteString.Lazy.Char8 as BL

import Control.Concurrent (threadDelay)

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "publishMsg" $ do
        context "with a routing key" $ do
            it "publishes a message" $ do
                let q = "haskell-amqp.queues.publish-over-default-exchange1"
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn

                (_, n1, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n1 `shouldBe` 0

                -- publishes using default exchange
                publishMsg ch "" q
                    (newMsg {msgBody = (BL.pack "hello")})
                threadDelay (1000 * 100)

                (_, n2, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n2 `shouldBe` 1

                n3 <- deleteQueue ch q
                n3 `shouldBe` 1
                closeConnection conn

        context "with a blank routing key" $ do
            it "publishes a message" $ do
                let q = "haskell-amqp.queues.publish-over-fanout1"
                    e = "haskell-amqp.fanout.d.na"
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn

                _    <- declareExchange ch (newExchange {exchangeName = e,
                                                         exchangeType = "fanout",
                                                         exchangeDurable = True})

                (_, _, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                _ <- purgeQueue ch q
                bindQueue ch q e ""

                -- publishes using default exchange
                publishMsg ch e ""
                    (newMsg {msgBody = (BL.pack "hello")})
                threadDelay (100 * 100)

                (_, n, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n `shouldBe` 1

                _ <- deleteQueue ch q
                closeConnection conn
