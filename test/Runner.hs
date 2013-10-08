import Test.Hspec

import qualified ConnectionSpec

main :: IO ()
main = hspec $ do
  describe "ConnectionSpec" ConnectionSpec.spec
