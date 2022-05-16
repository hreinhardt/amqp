package = amqp
exe = amqp-builder

run:
	cabal run $(exe)

run-fast:
	cabal run $(exe) --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build:
	cabal build $(package) --ghc-options "-j6 +RTS -A128m -n2m -qg -RTS"

build-fast:
	cabal build $(package) --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build-examples:
	cabal build amqp-example-confirms amqp-example-consumer amqp-example-producer amqp-example-tls-consumer amqp-example-tls-producer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

.PHONY : run run-fast build build-fast build-examples

