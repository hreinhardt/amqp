module IdAllocatorSpec (main, spec) where

import Test.Hspec
import Network.AMQP.Helpers

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "IdAllocator" $ do
        it "starts with id 1" $ do
            alloc <- newIdAllocator 10
            i <- nextId alloc
            i `shouldBe` Just 1

        it "returns the lowest free id" $ do
            alloc <- newIdAllocator 10
            _1 <- nextId alloc
            _2 <- nextId alloc
            _3 <- nextId alloc

            _1 `shouldBe` Just 1
            _2 `shouldBe` Just 2
            _3 `shouldBe` Just 3

            releaseId alloc 2

            _2' <- nextId alloc
            _2' `shouldBe` Just 2

        it "doesn't return ids higher than the configured max id" $ do
            alloc <- newIdAllocator 1
            _1 <- nextId alloc
            _2 <- nextId alloc

            _1 `shouldBe` Just 1
            _2 `shouldBe` Nothing