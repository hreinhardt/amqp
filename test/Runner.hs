import Test.Hspec

import qualified ConnectionSpec
import qualified ChannelSpec
import qualified QueueDeclareSpec
import qualified QueueDeleteSpec       
import qualified ExchangeDeclareSpec

main :: IO ()
main = hspec $ do
    -- connection.*
    describe "ConnectionSpec"      ConnectionSpec.spec
    -- channel.*
    describe "ChannelSpec"         ChannelSpec.spec
    -- queue.declare
    describe "QueueDeclareSpec"    QueueDeclareSpec.spec
    -- exchange.declare
    describe "ExchangeDeclareSpec" ExchangeDeclareSpec.spec
    -- queue.delete
    describe "QueueDeleteSpec"     QueueDeleteSpec.spec
