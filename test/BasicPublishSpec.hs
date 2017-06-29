{-# OPTIONS -XOverloadedStrings #-}

module BasicPublishSpec (main, spec) where

import Test.Hspec
import Network.AMQP

import Data.ByteString.Lazy.Char8 as BL
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Word

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM

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

                publishMsg ch e ""
                    (newMsg {msgBody = (BL.pack "hello")})
                threadDelay (1000 * 100)

                (_, n, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n `shouldBe` 1

                _ <- deleteQueue ch q
                closeConnection conn
        context "confirmSelect" $ do
            it "receives a confirmation message" $ do
                let q = "haskell-amqp.queues.publish-over-fanout1"
                    e = "haskell-amqp.fanout.d.na"
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn
                confirmSelect ch True
                (confirmMap, counter) <- atomically $ (,) <$> newTVar Map.empty <*> newTVar 0
                addConfirmationListener ch (handleConfirms counter confirmMap)
                _    <- declareExchange ch (newExchange {exchangeName = e,
                                                         exchangeType = "fanout",
                                                         exchangeDurable = True})

                (_, _, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                _ <- purgeQueue ch q
                bindQueue ch q e ""


                _ <- traverse (\n -> do
                                  sn' <- publishMsg ch e "" (newMsg {msgBody = (BL.pack "hello")})
                                  case sn' of
                                    Just sn -> atomically $ addSequenceNumber confirmMap (fromIntegral sn) n
                                    Nothing -> return ()

                              ) [1..5]


                threadDelay (1000 * 100)

                (_, n, _) <- declareQueue ch (newQueue {queueName = q, queueDurable = False})
                n `shouldBe` 5

                cMap' <- atomically $ readTVar confirmMap
                cMap' `shouldBe` Map.empty

                counter' <- atomically $ readTVar counter
                counter' `shouldSatisfy` (>0)

                _ <- deleteQueue ch q
                closeConnection conn


addSequenceNumber :: TVar (Map Word64 Int) -> Word64 -> Int -> STM ()
addSequenceNumber cMap sn n = modifyTVar' cMap (Map.insert sn n)

removeSequenceNumber :: TVar (Map Word64 Int) -> Word64 -> STM ()
removeSequenceNumber cMap sn = modifyTVar' cMap (Map.delete sn)

increaseCounter :: TVar Int -> STM ()
increaseCounter n = modifyTVar' n (+1)

handleConfirms :: TVar Int -> TVar (Map Word64 Int) -> (Word64, Bool, AckType) -> IO ()
handleConfirms c _ (_, False, BasicNack) = atomically $ increaseCounter c
handleConfirms c _ (_, True, BasicNack) = atomically $ increaseCounter c
handleConfirms c cMap (n, False, BasicAck) = atomically $ removeSequenceNumber cMap n >> increaseCounter c
handleConfirms c cMap (n, True, BasicAck) = atomically $ do
  increaseCounter c
  cMap' <- readTVar cMap
  let (lt, eq', _) = Map.splitLookup n cMap'
  case eq' of
    Just _ -> removeSequenceNumber cMap n
    Nothing -> return ()
  _ <- traverse (removeSequenceNumber cMap) (Map.keys lt)
  return ()
