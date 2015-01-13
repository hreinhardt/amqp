@echo off

:: ${RABBITMQCTL:="sudo rabbitmqctl"}
:: ${RABBITMQ_PLUGINS:="sudo rabbitmq-plugins"}

:: guest:guest has full access to /

cmd /C rabbitmqctl add_vhost /
cmd /C rabbitmqctl add_user guest guest
cmd /C rabbitmqctl set_permissions -p / guest ".*" ".*" ".*"

:: haskell_amqp:haskell_amqp_password has full access to haskell_amqp_testbed

cmd /C rabbitmqctl add_vhost haskell_amqp_testbed
cmd /C rabbitmqctl add_user haskell_amqp haskell_amqp_password
cmd /C rabbitmqctl set_permissions -p haskell_amqp_testbed haskell_amqp ".*" ".*" ".*"

:: guest:guest has full access to haskell_amqp_testbed

cmd /C rabbitmqctl set_permissions -p haskell_amqp_testbed guest ".*" ".*" ".*"

:: haskell_amqp_reader:reader_password has read access to haskell_amqp_testbed

cmd /C rabbitmqctl add_user haskell_amqp_reader reader_password
cmd /C rabbitmqctl set_permissions -p haskell_amqp_testbed haskell_amqp_reader "^---$" "^---$" ".*"
