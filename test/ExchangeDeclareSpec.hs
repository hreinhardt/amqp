{-# OPTIONS -XOverloadedStrings #-}

module ExchangeDeclareSpec (main, spec) where

import Test.Hspec
import Network.AMQP

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "declareExchange" $ do
        context "client-named, fanout, durable, non-autodelete" $ do
            it "declares the exchange" $ do
                let eName = "haskell-amqp.fanout.d.na"

                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn

                _    <- declareExchange ch (newExchange {exchangeName = eName,
                                                         exchangeType = "fanout",
                                                         exchangeDurable = True})


                _    <- declareExchange ch (newExchange {exchangeName    = eName,
                                                         exchangePassive = True})

                closeConnection conn

        context "client-named, topic, non-durable, non-autodelete" $ do
            it "declares the exchange" $ do
                let eName = "haskell-amqp.topic.nd.na"

                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn

                _    <- declareExchange ch (newExchange {exchangeName = eName,
                                                         exchangeType = "topic",
                                                         exchangeDurable = False})


                _    <- declareExchange ch (newExchange {exchangeName    = eName,
                                                         exchangePassive = True})

                closeConnection conn
