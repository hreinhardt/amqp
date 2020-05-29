### Version 0.20.0

* `fromURI` now activates TLS if the URI starts with `ampqs://`. Previously it only changed the port, without activating TLS.
* `fromURI` now supports multi-broker URIs in the form of `amqp://user:pass@host-1:port-2,host-2:port-2/vhost`

### Version 0.19.1

* add `nackMsg` and `nackEnv` methods

### Version 0.19.0

* change `FVString` to be binary instead of UTF-8 encoded

### Version 0.18.3

* respond to `channel.close` messages from the server with `channel.close_ok`

### Version 0.18.2

* support `connection` 0.3 and drop support for `network` < 2.6

### Version 0.18.1

* new function `addConnectionBlockedHandler` to be notified when the connection is blocked (due to the server being resource-constrained)

### Version 0.18.0

* `ConnectionClosedException` and `ChannelClosedException` now specify whether the close was normal (user-initiated) or abnormal (caused by an AMQP exception)
* channels that are abnormally closed and have no exception handler (set using `addChannelExceptionHandler`) will now print the error to `stderr`
* new function `getServerProperties` to get the RabbitMQ server-properties
* `consumeMsgs'` now allows setting a consumer-cancellation-callback

### Version 0.17.0

* When the server asynchronously closed a channel, this was (erroneously) internally represented as a `ConnectionClosedException`. It is now represented as a `ChannelClosedException`. This could affect you if you explicitly match on `ConnectionClosedException` or `ChannelClosedException` in your code, for example when using `addChannelExceptionHandler`.

### Version 0.16.0

* new `coName` field in `ConnectionOpts` to specify a custom name that will be displayed in the RabbitMQ web interface

### Version 0.15.1

* export the `AckType` data-type and constructors

### Version 0.15.0

* The way channels are closed internally was changed. This may affect you if you have installed an exception handler inside the callback passed to `consumeMsgs`. Specifically, the exceptions used internally to close channels are now wrapped inside `ChanThreadKilledException`. You should make sure to re-throw this exception if you did catch it.

### Version 0.14.1

* show all exceptions if no host can be connected to

### Version 0.14.0

* publishMsg now returns the message sequence-number
* new `TLSCustom` field in `TLSSettings`

### Version 0.13.1

* don't print to stderr when `openConnection` fails to connect to a broker

### Version 0.13.0

* support for [RabbitMQ publisher confirms](http://www.rabbitmq.com/confirms.html)

### Version 0.12.3

* send version info of this library to RabbitMQ on connecting

### Version 0.12.2

* GHC 7.10 compatibility

### Version 0.12.1

* error messages now go to stderr

### Version 0.12.0

* new function addChannelExceptionHandler

### Version 0.11.0

* all content fields for messages are now supported

### Version 0.10.0

* the maximum number of channels can now be set

### Version 0.9.0

* add 'global' flag for qos

### Version 0.8.3

* implement closeChannel

### Version 0.8.0

* TLS support
* new helper function rejectEnv
* new field exchangeArguments in ExchangeOpts
* new module Network.AMQP.Lifted with consumeMsgs functions lifted to MonadBaseControl

### Version 0.7.0

* new function fromURI to parse AMQP URIs
* heartbeat support

### Version 0.6.0

* new function addReturnListener which allows specifying a handler for returned messages
* new function openConnection'' with support for most AMQP connection options
* better error message on failed connection handshake

### Version 0.5.0

* support for AMQP 0-9-1
* new function consumeMsgs' which allows you to pass in a field-table
* new function bindExchange allows for binding an exchange to another exchange
* new function unbindQueue allows unbinding a queue from an exchange
* new function unbindExchange allows unbinding an exchange from an exchange

### Version 0.4.3

* use Handles instead of sockets
* fix deprecation warnings from Data.Binary

### Version 0.4.2

* add (Read, Ord, Eq, Show) instances for most data-types

### Version 0.4.1

* add queueHeaders field to QueueOpts

### Version 0.4

* Data.Text is now used instead of Strings. Using the _OverloadedStrings_ extension will make upgrading easier
* the field-types in Network.AMQP.Types should now be more compatible with RabbitMQ
* hostnames passed to openConnection will now be resolved
* basic QoS support
* exceptions thrown in a callback will not erroneously close the channel anymore
