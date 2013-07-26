AMQP
=====

Library for accessing RabbitMQ from Haskell. Please see the [Hackage docs](http://hackage.haskell.org/packages/archive/amqp/latest/doc/html/Network-AMQP.html) for an example.

Changelog
=========

### Version 0.4.1

* add queueHeaders field to QueueOpts

### Version 0.4

* Data.Text is now used instead of Strings. Using the _OverloadedStrings_ extension will make upgrading easier
* the field-types in Network.AMQP.Types should now be more compatible with RabbitMQ
* hostnames passed to openConnection will now be resolved
* basic QoS support
* exceptions thrown in a callback will not erroneously close the channel anymore