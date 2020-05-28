{-# OPTIONS -XOverloadedStrings #-}


module FromURISpec (main, spec) where


import              Data.Maybe                              (isNothing)
import              Network.AMQP
import              Test.Hspec


main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "fromURI" $ do
        it "empty" $ do
            let o = fromURI ""
            coServers o `shouldBe` [("localhost", 5672)]
            coVHost o `shouldBe` "/"
            -- avoid undefined SASLMechanism Show instance
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULguest\NULguest"]
            -- avoid undefined TLSSettings Show instance
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host" $ do
            let o = fromURI "amqp://u:p@127.0.0.1"
            coServers o `shouldBe` [("127.0.0.1", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host-2" $ do
            let o = fromURI "amqp://u:p@127.0.0.1,127.0.0.2"
            coServers o `shouldBe` [("127.0.0.1", 5672),("127.0.0.2", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host port" $ do
            let o = fromURI "amqp://u:p@127.0.0.1:5672"
            coServers o `shouldBe` [("127.0.0.1", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host-2 port" $ do
            let o = fromURI "amqp://u:p@127.0.0.1,127.0.0.2:5672"
            coServers o `shouldBe` [("127.0.0.1", 5672),("127.0.0.2", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host-2 port-2" $ do
            let o = fromURI "amqp://u:p@127.0.0.1:5672,127.0.0.2:5672"
            coServers o `shouldBe` [("127.0.0.1", 5672),("127.0.0.2", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host port vhost" $ do
            let o = fromURI "amqp://u:p@127.0.0.1:5672/v"
            coServers o `shouldBe` [("127.0.0.1", 5672)]
            coVHost o `shouldBe` "v"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host-2 port-2 vhost" $ do
            let o = fromURI "amqp://u:p@127.0.0.1:5673,127.0.0.2:5674/v"
            coServers o `shouldBe` [("127.0.0.1", 5673),("127.0.0.2", 5674)]
            coVHost o `shouldBe` "v"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp auth host-3 port-3 vhost" $ do
            let o = fromURI "amqp://a:b@h1:8001,h2:8002,h3:8003/w"
            coServers o `shouldBe` [("h1", 8001),("h2", 8002),("h3", 8003)]
            coVHost o `shouldBe` "w"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULa\NULb"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp host" $ do
            let o = fromURI "amqp://127.0.0.1"
            -- this appears to break: user host
            coServers o `shouldBe` [("localhost", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe`
                ["\NUL127.0.0.1\NULguest"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqp host-2" $ do
            let o = fromURI "amqp://127.0.0.1,127.0.0.2"
            -- this appears to break: user host
            coServers o `shouldBe` [("localhost", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe`
                ["\NUL127.0.0.1,127.0.0.2\NULguest"]
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps auth host" $ do
            let o = fromURI "amqps://u:p@127.0.0.1"
            coServers o `shouldBe` [("127.0.0.1", 5671)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps auth host-2" $ do
            let o = fromURI "amqps://u:p@127.0.0.1,127.0.0.2"
            coServers o `shouldBe` [("127.0.0.1", 5671),("127.0.0.2", 5671)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps auth host port" $ do
            let o = fromURI "amqps://u:p@127.0.0.1:5672"
            coServers o `shouldBe` [("127.0.0.1", 5672)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps auth host-2 port" $ do
            let o = fromURI "amqps://u:p@127.0.0.1,127.0.0.1:5673"
            coServers o `shouldBe` [("127.0.0.1", 5671),("127.0.0.1", 5673)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps auth host-2 port-2" $ do
            let o = fromURI "amqps://u:p@127.0.0.1:5672,127.0.0.1:5673"
            coServers o `shouldBe` [("127.0.0.1", 5672),("127.0.0.1", 5673)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps auth host port vhost" $ do
            let o = fromURI "amqps://u:p@127.0.0.1:5672/v"
            coServers o `shouldBe` [("127.0.0.1", 5672)]
            coVHost o `shouldBe` "v"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps auth host-2 port-2 vhost" $ do
            let o = fromURI "amqps://u:p@127.0.0.1:5672,127.0.0.2:5673/v"
            coServers o `shouldBe` [("127.0.0.1", 5672),("127.0.0.2", 5673)]
            coVHost o `shouldBe` "v"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe` ["\NULu\NULp"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps host" $ do
            let o = fromURI "amqps://127.0.0.1"
            -- this appears to break: user host
            coServers o `shouldBe` [("localhost", 5671)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe`
                ["\NUL127.0.0.1\NULguest"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
        
        it "amqps host-2" $ do
            let o = fromURI "amqps://127.0.0.1,127.0.0.2"
            -- this appears to break: user host
            coServers o `shouldBe` [("localhost", 5671)]
            coVHost o `shouldBe` "/"
            (saslName <$> coAuth o) `shouldBe` ["PLAIN"]
            (saslInitialResponse <$> coAuth o) `shouldBe`
                ["\NUL127.0.0.1,127.0.0.2\NULguest"]
            -- amqps protocol does not activate TLS!
            (isNothing $ coTLSSettings o) `shouldBe` True
