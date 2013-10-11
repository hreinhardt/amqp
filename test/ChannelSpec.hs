{-# OPTIONS -XOverloadedStrings #-}

module ChannelSpec (main, spec) where

import Test.Hspec
import Network.AMQP

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "openChannel" $ do
    context "with automatically allocated channel id" $ do
      it "opens a new channel with unique id" $ do
        conn <- openConnection "127.0.0.1" "/" "guest" "guest"
        ch   <- openChannel conn

        -- use the channel to avoid warnings
        qos ch 0 64
        -- TODO: assert on channel id

        closeConnection conn
