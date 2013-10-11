import Test.Hspec

import qualified ConnectionSpec
import qualified ChannelSpec

main :: IO ()
main = hspec $ do
  describe "ConnectionSpec" ConnectionSpec.spec
  describe "ChannelSpec"    ChannelSpec.spec
