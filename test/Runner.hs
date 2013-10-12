import Test.Hspec

import qualified ConnectionSpec
import qualified ChannelSpec
import qualified QueueDeclareSpec

main :: IO ()
main = hspec $ do
  -- connection.*
  describe "ConnectionSpec" ConnectionSpec.spec
  -- channel.*
  describe "ChannelSpec"    ChannelSpec.spec
  -- queue.declare
  describe "QueueDeclareSpec"    QueueDeclareSpec.spec
