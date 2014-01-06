{-# OPTIONS -XOverloadedStrings #-}

module BasicRejectSpec (main, spec) where

import Test.Hspec
import Network.AMQP

import Data.ByteString.Lazy.Char8 as L8
import Control.Concurrent (threadDelay)
import Control.Exception (bracket)

main :: IO ()
main = hspec spec

withTestConnection :: (Channel -> IO c) -> IO c
withTestConnection job = do
    bracket (openConnection "127.0.0.1" "/" "guest" "guest") closeConnection $ \conn -> do
        ch <- openChannel conn
        job ch

spec :: Spec
spec = do
    describe "rejectMsg" $ do
        context "requeue = True" $ do
            it "requeues a message" $ withTestConnection $ \ch -> do
                let q = "haskell-amqp.basic.reject.with-requeue-true"

                (_, n1, _) <- declareQueue ch $ newQueue {queueName = q, queueDurable = False}
                n1 `shouldBe` 0

                -- publishes using default exchange
                publishMsg ch "" q $ newMsg {msgBody = (L8.pack "hello")}
                threadDelay (1000 * 100)

                (_, n2, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n2 `shouldBe` 1

                Just (_msg, env) <- getMsg ch Ack q
                rejectMsg (envChannel env) (envDeliveryTag env) True
                threadDelay (1000 * 100)

                n3 <- deleteQueue ch q
                n3 `shouldBe` 1

        context "requeue = False" $ do
            it "rejects a message" $ withTestConnection $ \ch -> do
                let q = "haskell-amqp.basic.reject.with-requeue-false"

                (_, n1, _) <- declareQueue ch $ newQueue {queueName = q, queueDurable = False}
                n1 `shouldBe` 0

                -- publishes using default exchange
                publishMsg ch "" q $ newMsg {msgBody = (L8.pack "hello")}
                threadDelay (1000 * 100)

                (_, n2, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n2 `shouldBe` 1

                Just (_msg, env) <- getMsg ch Ack q
                rejectMsg (envChannel env) (envDeliveryTag env) False
                threadDelay (1000 * 100)

                n3 <- deleteQueue ch q
                n3 `shouldBe` 0

    describe "rejectEnv" $ do
        context "requeue = True" $ do
            it "requeues a message" $ withTestConnection $ \ch -> do
                let q = "haskell-amqp.basic.reject.with-requeue-true"

                (_, n1, _) <- declareQueue ch $ newQueue {queueName = q, queueDurable = False}
                n1 `shouldBe` 0

                -- publishes using default exchange
                publishMsg ch "" q $ newMsg {msgBody = (L8.pack "hello")}
                threadDelay (1000 * 100)

                (_, n2, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n2 `shouldBe` 1

                Just (_msg, env) <- getMsg ch Ack q
                rejectEnv env True
                threadDelay (1000 * 100)

                n3 <- deleteQueue ch q
                n3 `shouldBe` 1

        context "requeue = False" $ do
            it "rejects a message" $ withTestConnection $ \ch -> do
                let q = "haskell-amqp.basic.reject.with-requeue-false"

                (_, n1, _) <- declareQueue ch $ newQueue {queueName = q, queueDurable = False}
                n1 `shouldBe` 0

                -- publishes using default exchange
                publishMsg ch "" q $ newMsg {msgBody = (L8.pack "hello")}
                threadDelay (1000 * 100)

                (_, n2, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n2 `shouldBe` 1

                Just (_msg, env) <- getMsg ch Ack q
                rejectEnv env False
                threadDelay (1000 * 100)

                n3 <- deleteQueue ch q
                n3 `shouldBe` 0
