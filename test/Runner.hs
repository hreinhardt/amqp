import Test.Hspec

import qualified ConnectionSpec
import qualified ChannelSpec
import qualified QueueDeclareSpec
import qualified QueueDeleteSpec
import qualified QueuePurgeSpec
import qualified ExchangeDeclareSpec
import qualified ExchangeDeleteSpec

main :: IO ()
main = hspec $ do
    -- connection.*
    describe "ConnectionSpec"      ConnectionSpec.spec
    -- channel.*
    describe "ChannelSpec"         ChannelSpec.spec
    -- exchange.declare
    describe "ExchangeDeclareSpec" ExchangeDeclareSpec.spec
    -- exchange.delete
    describe "ExchangeDeleteSpec"  ExchangeDeleteSpec.spec
    -- queue.declare
    describe "QueueDeclareSpec"    QueueDeclareSpec.spec
    -- queue.delete
    describe "QueueDeleteSpec"     QueueDeleteSpec.spec
    -- queue.purge
    describe "QueuePurgeSpec"      QueuePurgeSpec.spec
