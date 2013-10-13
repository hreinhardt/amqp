{-# OPTIONS -XOverloadedStrings #-}

module ConnectionSpec (main, spec) where

import Test.Hspec
import Network.AMQP

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "openConnection" $ do
        context "with default vhost and default admin credentials" $ do
            it "connects successfully" $ do
                conn <- openConnection "127.0.0.1" "/" "guest" "guest"
                closeConnection conn

        context "with custom vhost and valid credentials" $ do
            it "connects successfully" $ do
                -- see ./bin/ci/before_build.sh
                conn <- openConnection "127.0.0.1" "haskell_amqp_testbed"
                                                   "haskell_amqp"
                                                   "haskell_amqp_password"
                closeConnection conn
