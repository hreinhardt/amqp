{-# OPTIONS -XOverloadedStrings #-}

module QueuePurgeSpec (main, spec) where

import Test.Hspec
import Network.AMQP

import Data.ByteString.Lazy.Char8 as BL hiding (putStrLn)
import Control.Concurrent (threadDelay)

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
     describe "purgeQueue" $ do
         context "when queue exists" $ do
             it "empties the queue" $ do
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn

                (q, _, _) <- declareQueue ch (newQueue {queueName       = "",
                                                        queueDurable    = True,
                                                        queueExclusive  = False,
                                                        queueAutoDelete = False})

                publishMsg ch "" q
                           newMsg {msgBody = (BL.pack "payload")}

                threadDelay (1000 * 100)
                (_, n, _) <- declareQueue ch (newQueue {queueName       = q,
                                                        queuePassive    = True})
                n `shouldBe` 1
                _ <- purgeQueue ch q

                threadDelay (1000 * 100)
                (_, n2, _) <- declareQueue ch (newQueue {queueName       = q,
                                                         queuePassive    = True})
                n2 `shouldBe` 0
                closeConnection conn

         context "when queue DOES NOT exist" $ do
             it "empties the queue" $ do
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn

                let ex = ChannelClosedException "NOT_FOUND - no queue 'haskell-amqp.queues.avjqmyG{CHrc66MRyzYVA+PwrMVARJ' in vhost '/'"
                (purgeQueue ch "haskell-amqp.queues.avjqmyG{CHrc66MRyzYVA+PwrMVARJ") `shouldThrow` (== ex)

                closeConnection conn
