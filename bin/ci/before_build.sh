#!/bin/sh

${RABBITMQCTL:="sudo rabbitmqctl"}
${RABBITMQ_PLUGINS:="sudo rabbitmq-plugins"}

# guest:guest has full access to /

$RABBITMQCTL add_vhost /
$RABBITMQCTL add_user guest guest
$RABBITMQCTL set_permissions -p / guest ".*" ".*" ".*"

# haskell_amqp:haskell_amqp_password has full access to haskell_amqp_testbed

$RABBITMQCTL add_vhost haskell_amqp_testbed
$RABBITMQCTL add_user haskell_amqp haskell_amqp_password
$RABBITMQCTL set_permissions -p haskell_amqp_testbed haskell_amqp ".*" ".*" ".*"

# guest:guest has full access to haskell_amqp_testbed

$RABBITMQCTL set_permissions -p haskell_amqp_testbed guest ".*" ".*" ".*"


# haskell_amqp_reader:reader_password has read access to haskell_amqp_testbed

$RABBITMQCTL add_user haskell_amqp_reader reader_password
$RABBITMQCTL set_permissions -p haskell_amqp_testbed haskell_amqp_reader "^---$" "^---$" ".*"
