{-# OPTIONS -XOverloadedStrings #-}

module QueueDeclareSpec (main, spec) where

import Test.Hspec
import Network.AMQP


main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "declareQueue" $ do
    context "client named, durable, non-autodelete, non-exclusive" $ do
      it "declares the queue" $ do
        conn <- openConnection "127.0.0.1" "/" "guest" "guest"
        ch   <- openChannel conn

        _    <- declareQueue ch (newQueue {queueName       = qName,
                                           queueDurable    = True,
                                           queueExclusive  = False,
                                           queueAutoDelete = False})

        _     <- declareQueue ch (newQueue {queueName = qName, queuePassive = True})

        closeConnection conn
        where
          qName = "haskell-amqp.client-named.d.na.ne"