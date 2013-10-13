{-# OPTIONS -XOverloadedStrings #-}

module ChannelSpec (main, spec) where

import Test.Hspec
import Network.AMQP
import Network.AMQP.Internal (channelID)

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "openChannel" $ do
        context "with automatically allocated channel id" $ do
            it "opens a new channel with unique id" $ do
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch1  <- openChannel conn
                ch2  <- openChannel conn
                ch3  <- openChannel conn

                channelID ch1 `shouldBe` 1
                channelID ch2 `shouldBe` 2
                channelID ch3 `shouldBe` 3

                closeConnection conn

    describe "closeChannel" $ do
        context "with an open channel" $ do
            it "closes the channel" $ do
                pending

    describe "qos" $ do
        context "with prefetchCount = 5" $ do
            it "sets prefetch count" $ do
                -- we won't demonstrate how basic.qos works in concert
                -- with acks here, it's more of a basic.consume functionality
                -- aspect
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                ch   <- openChannel conn

                qos ch 0 5

                closeConnection conn
