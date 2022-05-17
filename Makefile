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


build-example-confirms:
	cd examples/confirms && cabal build amqp-example-confirms --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build-example-consumer:
	cd examples/consumer && cabal build amqp-example-consumer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build-example-producer:
	cd examples/producer && cabal build amqp-example-producer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build-example-tls-consumer:
	cd examples/tlsConsumer && cabal build amqp-example-tls-consumer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build-example-tls-producer:
	cd examples/tlsProducer && cabal build amqp-example-tls-producer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build-example-connection-management:
	cd examples/connectionManagement && cabal build amqp-example-connection-management --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

build-examples: build-example-confirms build-example-consumer build-example-producer build-example-tls-consumer build-example-tls-producer build-example-connection-management


run-example-confirms:
	cd examples/confirms && cabal run amqp-example-confirms --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

run-example-consumer:
	cd examples/consumer && cabal run amqp-example-consumer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

run-example-producer:
	cd examples/producer && cabal run amqp-example-producer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

run-example-tls-consumer:
	cd examples/tlsConsumer && cabal run amqp-example-tls-consumer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

run-example-tls-producer:
	cd examples/tlsProducer && cabal run amqp-example-tls-producer --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

run-example-connection-management:
	cd examples/connectionManagement && cabal run amqp-example-connection-management --disable-optimisation --ghc-options "-O0 -j6 +RTS -A128m -n2m -qg -RTS"

.PHONY : run run-fast build build-fast build-examples build-example-confirms build-example-consumer build-example-producer build-example-tls-consumer build-example-tls-producer build-example-connection-management



