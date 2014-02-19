{-# LANGUAGE BangPatterns, DeriveDataTypeable, OverloadedStrings, ScopedTypeVariables #-}
-- |
--
-- A client library for AMQP servers implementing the 0-9-1 spec; currently only supports RabbitMQ (see <http://www.rabbitmq.com>)
--
-- A good introduction to RabbitMQ and AMQP 0-9-1 (in various languages): <http://www.rabbitmq.com/getstarted.html>, <http://www.rabbitmq.com/tutorials/amqp-concepts.html>
--
-- /Example/:
--
-- Connect to a server, declare a queue and an exchange and setup a callback for messages coming in on the queue. Then publish a single message to our new exchange
--
-- >{-# LANGUAGE OverloadedStrings #-}
-- >import Network.AMQP
-- >import qualified Data.ByteString.Lazy.Char8 as BL
-- >
-- >main = do
-- >    conn <- openConnection "127.0.0.1" "/" "guest" "guest"
-- >    chan <- openChannel conn
-- >
-- >    -- declare a queue, exchange and binding
-- >    declareQueue chan newQueue {queueName = "myQueue"}
-- >    declareExchange chan newExchange {exchangeName = "myExchange", exchangeType = "direct"}
-- >    bindQueue chan "myQueue" "myExchange" "myKey"
-- >
-- >    -- subscribe to the queue
-- >    consumeMsgs chan "myQueue" Ack myCallback
-- >
-- >    -- publish a message to our new exchange
-- >    publishMsg chan "myExchange" "myKey"
-- >        newMsg {msgBody = (BL.pack "hello world"),
-- >                msgDeliveryMode = Just Persistent}
-- >
-- >    getLine -- wait for keypress
-- >    closeConnection conn
-- >    putStrLn "connection closed"
-- >
-- >
-- >myCallback :: (Message,Envelope) -> IO ()
-- >myCallback (msg, env) = do
-- >    putStrLn $ "received message: " ++ (BL.unpack $ msgBody msg)
-- >    -- acknowledge receiving the message
-- >    ackEnv env
--
-- /Exception handling/:
--
-- Some function calls can make the AMQP server throw an AMQP exception, which has the side-effect of closing the connection or channel. The AMQP exceptions are raised as Haskell exceptions (see 'AMQPException'). So upon receiving an 'AMQPException' you may have to reopen the channel or connection.

module Network.AMQP (
    -- * Connection
    Connection,
    ConnectionOpts(..),
    TLSSettings(..),
    defaultConnectionOpts,
    openConnection,
    openConnection',
    openConnection'',
    closeConnection,
    addConnectionClosedHandler,

    -- * Channel
    Channel,
    openChannel,
    addReturnListener,
    qos,

    -- * Exchanges
    ExchangeOpts(..),
    newExchange,
    declareExchange,
    bindExchange,
    bindExchange',
    unbindExchange,
    unbindExchange',
    deleteExchange,

    -- * Queues
    QueueOpts(..),
    newQueue,
    declareQueue,
    bindQueue,
    bindQueue',
    unbindQueue,
    unbindQueue',
    purgeQueue,
    deleteQueue,

    -- * Messaging
    Message(..),
    DeliveryMode(..),
    PublishError(..),
    ReturnReplyCode(..),
    newMsg,
    Envelope(..),
    ConsumerTag,
    Ack(..),
    consumeMsgs,
    consumeMsgs',
    cancelConsumer,
    publishMsg,
    publishMsg',
    getMsg,
    rejectMsg,
    rejectEnv,
    recoverMsgs,

    ackMsg,
    ackEnv,

    -- * Transactions
    txSelect,
    txCommit,
    txRollback,

    -- * Flow Control
    flow,

    -- * SASL
    SASLMechanism(..),
    plain,
    amqplain,
    rabbitCRdemo,

    -- * Exceptions
    AMQPException(..),

    -- * URI parsing
    fromURI
) where

import Control.Concurrent
import Data.List.Split (splitOn)
import Data.Binary
import Data.Binary.Put
import Network
import Network.URI (unEscapeString)
import Data.Text (Text)

import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as E
import qualified Data.Map as M
import qualified Data.Text as T

import Network.AMQP.Types
import Network.AMQP.Generated
import Network.AMQP.Internal
import Network.AMQP.Helpers

----- EXCHANGE -----

-- | A record that contains the fields needed when creating a new exhange using 'declareExchange'. The default values apply when you use 'newExchange'.
data ExchangeOpts = ExchangeOpts
                {
                    exchangeName :: Text, -- ^ (must be set); the name of the exchange
                    exchangeType :: Text, -- ^ (must be set); the type of the exchange (\"fanout\", \"direct\", \"topic\", \"headers\")

                    -- optional
                    exchangePassive :: Bool, -- ^ (default 'False'); If set, the server will not create the exchange. The client can use this to check whether an exchange exists without modifying the server state.
                    exchangeDurable :: Bool, -- ^ (default 'True'); If set when creating a new exchange, the exchange will be marked as durable. Durable exchanges remain active when a server restarts. Non-durable exchanges (transient exchanges) are purged if/when a server restarts.
                    exchangeAutoDelete :: Bool, -- ^ (default 'False'); If set, the exchange is deleted when all queues have finished using it.
                    exchangeInternal :: Bool, -- ^ (default 'False'); If set, the exchange may not be used directly by publishers, but only when bound to other exchanges. Internal exchanges are used to construct wiring that is not visible to applications.
                    exchangeArguments  :: FieldTable -- ^ (default empty); A set of arguments for the declaration. The syntax and semantics of these arguments depends on the server implementation.
                }
    deriving (Eq, Ord, Read, Show)

-- | an 'ExchangeOpts' with defaults set; you must override at least the 'exchangeName' and 'exchangeType' fields.
newExchange :: ExchangeOpts
newExchange = ExchangeOpts "" "" False True False False (FieldTable M.empty)

-- | declares a new exchange on the AMQP server. Can be used like this: @declareExchange channel newExchange {exchangeName = \"myExchange\", exchangeType = \"fanout\"}@
declareExchange :: Channel -> ExchangeOpts -> IO ()
declareExchange chan exchg = do
    (SimpleMethod Exchange_declare_ok) <- request chan (SimpleMethod (Exchange_declare
        1 -- ticket; ignored by rabbitMQ
        (ShortString $ exchangeName exchg) -- exchange
        (ShortString $ exchangeType exchg) -- typ
        (exchangePassive exchg) -- passive
        (exchangeDurable exchg) -- durable
        (exchangeAutoDelete exchg)  -- auto_delete
        (exchangeInternal exchg) -- internal
        False -- nowait
        (exchangeArguments exchg))) -- arguments
    return ()

-- | @bindExchange chan destinationName sourceName routingKey@ binds the exchange to the exchange using the provided routing key
bindExchange :: Channel -> Text -> Text -> Text -> IO ()
bindExchange chan destinationName sourceName routingKey =
    bindExchange' chan destinationName sourceName routingKey (FieldTable M.empty)

-- | an extended version of @bindExchange@ that allows you to include arbitrary arguments. This is useful to use the @headers@ exchange-type.
bindExchange' :: Channel -> Text -> Text -> Text -> FieldTable -> IO ()
bindExchange' chan destinationName sourceName routingKey args = do
    (SimpleMethod Exchange_bind_ok) <- request chan (SimpleMethod (Exchange_bind
        1 -- ticket; ignored by rabbitMQ
        (ShortString destinationName)
        (ShortString sourceName)
        (ShortString routingKey)
        False -- nowait
        args -- arguments
        ))
    return ()

-- | @unbindExchange chan destinationName sourceName routingKey@ unbinds an exchange from an exchange. The @routingKey@ must be identical to the one specified when binding the exchange.
unbindExchange :: Channel -> Text -> Text -> Text -> IO ()
unbindExchange chan destinationName sourceName routingKey =
  unbindExchange' chan destinationName sourceName routingKey (FieldTable M.empty)

-- | an extended version of @unbindExchange@ that allows you to include arguments. The @arguments@ must be identical to the ones specified when binding the exchange.
unbindExchange' :: Channel -> Text -> Text -> Text -> FieldTable -> IO ()
unbindExchange' chan destinationName sourceName routingKey args = do
    SimpleMethod Exchange_unbind_ok <- request chan $ SimpleMethod $ Exchange_unbind
        1 -- ticket
        (ShortString destinationName)
        (ShortString sourceName)
        (ShortString routingKey)
        False -- nowait
        args
    return ()

-- | deletes the exchange with the provided name
deleteExchange :: Channel -> Text -> IO ()
deleteExchange chan exchange = do
    (SimpleMethod Exchange_delete_ok) <- request chan (SimpleMethod (Exchange_delete
        1 -- ticket; ignored by rabbitMQ
        (ShortString exchange) -- exchange
        False -- if_unused;  If set, the server will only delete the exchange if it has no queue bindings.
        False -- nowait
        ))
    return ()

----- QUEUE -----

-- | A record that contains the fields needed when creating a new queue using 'declareQueue'. The default values apply when you use 'newQueue'.
data QueueOpts = QueueOpts
             {
                --must be set
                queueName :: Text, -- ^ (default \"\"); the name of the queue; if left empty, the server will generate a new name and return it from the 'declareQueue' method

                --optional
                queuePassive :: Bool, -- ^ (default 'False'); If set, the server will not create the queue.  The client can use this to check whether a queue exists without modifying the server state.
                queueDurable :: Bool, -- ^ (default 'True'); If set when creating a new queue, the queue will be marked as durable. Durable queues remain active when a server restarts. Non-durable queues (transient queues) are purged if/when a server restarts. Note that durable queues do not necessarily hold persistent messages, although it does not make sense to send persistent messages to a transient queue.
                queueExclusive :: Bool, -- ^ (default 'False'); Exclusive queues may only be consumed from by the current connection. Setting the 'exclusive' flag always implies 'auto-delete'.
                queueAutoDelete :: Bool, -- ^ (default 'False'); If set, the queue is deleted when all consumers have finished using it. Last consumer can be cancelled either explicitly or because its channel is closed. If there was no consumer ever on the queue, it won't be deleted.
                queueHeaders :: FieldTable -- ^ (default empty): Headers to use when creating this queue, such as @x-message-ttl@ or @x-dead-letter-exchange@.
             }
      deriving (Eq, Ord, Read, Show)

-- | a 'QueueOpts' with defaults set; you should override at least 'queueName'.
newQueue :: QueueOpts
newQueue = QueueOpts "" False True False False (FieldTable M.empty)

-- | creates a new queue on the AMQP server; can be used like this: @declareQueue channel newQueue {queueName = \"myQueue\"}@.
--
-- Returns a tuple @(queue, messageCount, consumerCount)@.
-- @queue@ is the name of the new queue (if you don't specify a queue the server will autogenerate one).
-- @messageCount@ is the number of messages in the queue, which will be zero for newly-created queues. @consumerCount@ is the number of active consumers for the queue.
declareQueue :: Channel -> QueueOpts -> IO (Text, Int, Int)
declareQueue chan queue = do
    (SimpleMethod (Queue_declare_ok (ShortString qName) messageCount consumerCount)) <- request chan $ (SimpleMethod (Queue_declare
            1 -- ticket
            (ShortString $ queueName queue)
            (queuePassive queue)
            (queueDurable queue)
            (queueExclusive queue)
            (queueAutoDelete queue)
            False -- no-wait; true means no answer from server
            (queueHeaders queue)))
    return (qName, fromIntegral messageCount, fromIntegral consumerCount)

-- | @bindQueue chan queue exchange routingKey@ binds the queue to the exchange using the provided routing key. If @exchange@ is the empty string, the default exchange will be used.
bindQueue :: Channel -> Text -> Text -> Text -> IO ()
bindQueue chan queue exchange routingKey = bindQueue' chan queue exchange routingKey (FieldTable M.empty)

-- | an extended version of @bindQueue@ that allows you to include arbitrary arguments. This is useful to use the @headers@ exchange-type.
bindQueue' :: Channel -> Text -> Text -> Text -> FieldTable -> IO ()
bindQueue' chan queue exchange routingKey args = do
    (SimpleMethod Queue_bind_ok) <- request chan (SimpleMethod (Queue_bind
        1 -- ticket; ignored by rabbitMQ
        (ShortString queue)
        (ShortString exchange)
        (ShortString routingKey)
        False -- nowait
        args -- arguments
        ))
    return ()

-- | @unbindQueue chan queue exchange routingKey@ unbinds a queue from an exchange. The @routingKey@ must be identical to the one specified when binding the queue.
unbindQueue :: Channel -> Text -> Text -> Text -> IO ()
unbindQueue chan queue exchange routingKey =
  unbindQueue' chan queue exchange routingKey (FieldTable M.empty)

-- | an extended version of @unbindQueue@ that allows you to include arguments. The @arguments@ must be identical to the ones specified when binding the queue.
unbindQueue' :: Channel -> Text -> Text -> Text -> FieldTable -> IO ()
unbindQueue' chan queue exchange routingKey args = do
    SimpleMethod Queue_unbind_ok <- request chan $ SimpleMethod $ Queue_unbind
        1 -- ticket
        (ShortString queue)
        (ShortString exchange)
        (ShortString routingKey)
        args
    return ()

-- | remove all messages from the queue; returns the number of messages that were in the queue
purgeQueue :: Channel -> Text -> IO Word32
purgeQueue chan queue = do
    (SimpleMethod (Queue_purge_ok msgCount)) <- request chan $ (SimpleMethod (Queue_purge
        1 -- ticket
        (ShortString queue) -- queue
        False -- nowait
        ))
    return msgCount

-- | deletes the queue; returns the number of messages that were in the queue before deletion
deleteQueue :: Channel -> Text -> IO Word32
deleteQueue chan queue = do
    (SimpleMethod (Queue_delete_ok msgCount)) <- request chan $ (SimpleMethod (Queue_delete
        1 -- ticket
        (ShortString queue) -- queue
        False -- if_unused
        False -- if_empty
        False -- nowait
        ))
    return msgCount

----- MSG (the BASIC class in AMQP) -----

-- | a 'Msg' with defaults set; you should override at least 'msgBody'
newMsg :: Message
newMsg = Message (BL.empty) Nothing Nothing Nothing Nothing Nothing Nothing Nothing

type ConsumerTag = Text

-- | specifies whether you have to acknowledge messages that you receive from 'consumeMsgs' or 'getMsg'. If you use 'Ack', you have to call 'ackMsg' or 'ackEnv' after you have processed a message, otherwise it might be delivered again in the future
data Ack = Ack | NoAck
  deriving (Eq, Ord, Read, Show)

ackToBool :: Ack -> Bool
ackToBool Ack = False
ackToBool NoAck = True

-- | @consumeMsgs chan queue ack callback@ subscribes to the given queue and returns a consumerTag. For any incoming message, the callback will be run. If @ack == 'Ack'@ you will have to acknowledge all incoming messages (see 'ackMsg' and 'ackEnv')
--
-- NOTE: The callback will be run on the same thread as the channel thread (every channel spawns its own thread to listen for incoming data) so DO NOT perform any request on @chan@ inside the callback (however, you CAN perform requests on other open channels inside the callback, though I wouldn't recommend it).
-- Functions that can safely be called on @chan@ are 'ackMsg', 'ackEnv', 'rejectMsg', 'recoverMsgs'. If you want to perform anything more complex, it's a good idea to wrap it inside 'forkIO'.
consumeMsgs :: Channel -> Text -> Ack -> ((Message,Envelope) -> IO ()) -> IO ConsumerTag
consumeMsgs chan queue ack callback =
  consumeMsgs' chan queue ack callback (FieldTable M.empty)

-- | an extended version of @consumeMsgs@ that allows you to include arbitrary arguments.
consumeMsgs' :: Channel -> Text -> Ack -> ((Message,Envelope) -> IO ()) -> FieldTable -> IO ConsumerTag
consumeMsgs' chan queue ack callback args = do
    --generate a new consumer tag
    newConsumerTag <- (fmap (T.pack . show)) $ modifyMVar (lastConsumerTag chan) $ \c -> return (c+1,c+1)

    --register the consumer
    modifyMVar_ (consumers chan) $ return . M.insert newConsumerTag callback

    writeAssembly chan (SimpleMethod $ Basic_consume
        1 -- ticket
        (ShortString queue) -- queue
        (ShortString newConsumerTag) -- consumer_tag
        False -- no_local; If the no-local field is set the server will not send messages to the client that published them.
        (ackToBool ack) -- no_ack
        False -- exclusive; Request exclusive consumer access, meaning only this consumer can access the queue.
        True -- nowait
        args
        )
    return newConsumerTag

-- | stops a consumer that was started with 'consumeMsgs'
cancelConsumer :: Channel -> ConsumerTag -> IO ()
cancelConsumer chan consumerTag = do
    (SimpleMethod (Basic_cancel_ok _)) <- request chan $ (SimpleMethod (Basic_cancel
        (ShortString consumerTag) -- consumer_tag
        False -- nowait
        ))

    --unregister the consumer
    modifyMVar_ (consumers chan) $ return . M.delete consumerTag

-- | @publishMsg chan exchange routingKey msg@ publishes @msg@ to the exchange with the provided @exchange@. The effect of @routingKey@ depends on the type of the exchange.
--
-- NOTE: This method may temporarily block if the AMQP server requested us to stop sending content data (using the flow control mechanism). So don't rely on this method returning immediately.
publishMsg :: Channel -> Text -> Text -> Message -> IO ()
publishMsg chan exchange routingKey msg = publishMsg' chan exchange routingKey False msg

-- | Like 'publishMsg', but additionally allows you to specify whether the 'mandatory' flag should be set.
publishMsg' :: Channel -> Text -> Text -> Bool -> Message -> IO ()
publishMsg' chan exchange routingKey mandatory msg = do
    writeAssembly chan (ContentMethod (Basic_publish
            1 -- ticket; ignored by rabbitMQ
            (ShortString exchange)
            (ShortString routingKey)
            mandatory -- mandatory; if true, the server might return the msg, which is currently not handled
            False) --immediate; not customizable, as it is currently not supported anymore by RabbitMQ

            --TODO: add more of these to 'Message'
            (CHBasic
            (fmap ShortString $ msgContentType msg)
            Nothing
            (msgHeaders msg)
            (fmap deliveryModeToInt $ msgDeliveryMode msg) -- delivery_mode
            Nothing
            (fmap ShortString $ msgCorrelationID msg)
            (fmap ShortString $ msgReplyTo msg)
            Nothing
            (fmap ShortString $ msgID msg)
            (msgTimestamp msg)
            Nothing
            Nothing
            Nothing
            Nothing
            )
            (msgBody msg))
    return ()

-- | @getMsg chan ack queue@ gets a message from the specified queue. If @ack=='Ack'@, you have to call 'ackMsg' or 'ackEnv' for any message that you get, otherwise it might be delivered again in the future (by calling 'recoverMsgs')
getMsg :: Channel -> Ack -> Text -> IO (Maybe (Message, Envelope))
getMsg chan ack queue = do
    ret <- request chan (SimpleMethod (Basic_get
        1 -- ticket
        (ShortString queue) -- queue
        (ackToBool ack) -- no_ack
        ))
    case ret of
        ContentMethod (Basic_get_ok deliveryTag redelivered (ShortString exchange) (ShortString routingKey) _) properties body ->
            return $ Just $ (msgFromContentHeaderProperties properties body,
                             Envelope {envDeliveryTag = deliveryTag, envRedelivered = redelivered,
                             envExchangeName = exchange, envRoutingKey = routingKey, envChannel = chan})
        _ -> return Nothing

{- | @ackMsg chan deliveryTag multiple@ acknowledges one or more messages. A message MUST not be acknowledged more than once.

if @multiple==True@, the @deliverTag@ is treated as \"up to and including\", so that the client can acknowledge multiple messages with a single method call. If @multiple==False@, @deliveryTag@ refers to a single message.

If @multiple==True@, and @deliveryTag==0@, tells the server to acknowledge all outstanding mesages.
-}
ackMsg :: Channel -> LongLongInt -> Bool -> IO ()
ackMsg chan deliveryTag multiple =
    writeAssembly chan $ (SimpleMethod (Basic_ack
        deliveryTag -- delivery_tag
        multiple -- multiple
        ))

-- | Acknowledges a single message. This is a wrapper for 'ackMsg' in case you have the 'Envelope' at hand.
ackEnv :: Envelope -> IO ()
ackEnv env = ackMsg (envChannel env) (envDeliveryTag env) False

-- | @rejectMsg chan deliveryTag requeue@ allows a client to reject a message. It can be used to interrupt and cancel large incoming messages, or return untreatable  messages to their original queue. If @requeue==False@, the message will be discarded.  If it is 'True', the server will attempt to requeue the message.
--
-- NOTE: RabbitMQ 1.7 doesn't implement this command
rejectMsg :: Channel -> LongLongInt -> Bool -> IO ()
rejectMsg chan deliveryTag requeue =
    writeAssembly chan $ (SimpleMethod (Basic_reject
        deliveryTag -- delivery_tag
        requeue -- requeue
        ))

-- | Reject a message. This is a wrapper for 'rejectMsg' in case you have the 'Envelope' at hand.
rejectEnv :: Envelope
          -> Bool -- ^ requeue
          -> IO ()
rejectEnv env requeue = rejectMsg (envChannel env) (envDeliveryTag env) requeue

-- | @recoverMsgs chan requeue@ asks the broker to redeliver all messages that were received but not acknowledged on the specified channel.
--If @requeue==False@, the message will be redelivered to the original recipient. If @requeue==True@, the server will attempt to requeue the message, potentially then delivering it to an alternative subscriber.
recoverMsgs :: Channel -> Bool -> IO ()
recoverMsgs chan requeue = do
    SimpleMethod Basic_recover_ok <- request chan $ (SimpleMethod (Basic_recover
        requeue -- requeue
        ))
    return ()

------------------- TRANSACTIONS (TX) --------------------------

-- | This method sets the channel to use standard transactions.  The client must use this method at least once on a channel before using the Commit or Rollback methods.
txSelect :: Channel -> IO ()
txSelect chan = do
    (SimpleMethod Tx_select_ok) <- request chan $ SimpleMethod Tx_select
    return ()

-- | This method commits all messages published and acknowledged in the current transaction.  A new transaction starts immediately after a commit.
txCommit :: Channel -> IO ()
txCommit chan = do
    (SimpleMethod Tx_commit_ok) <- request chan $ SimpleMethod Tx_commit
    return ()

-- | This method abandons all messages published and acknowledged in the current transaction. A new transaction starts immediately after a rollback.
txRollback :: Channel -> IO ()
txRollback chan = do
    (SimpleMethod Tx_rollback_ok) <- request chan $ SimpleMethod Tx_rollback
    return ()

--------------------- FLOW CONTROL ------------------------

{- | @flow chan active@ tells the AMQP server to pause or restart the flow of content
    data. This is a simple flow-control mechanism that a peer can use
    to avoid overflowing its queues or otherwise finding itself receiving
    more messages than it can process.

    If @active==True@ the server will start sending content data, if @active==False@ the server will stop sending content data.

    A new channel is always active by default.

    NOTE: RabbitMQ 1.7 doesn't implement this command.
    -}
flow :: Channel -> Bool -> IO ()
flow chan active = do
    (SimpleMethod (Channel_flow_ok _)) <- request chan $ SimpleMethod (Channel_flow active)
    return ()

-- | Constructs default connection options with the following settings :
--
--     * Broker: @amqp:\/\/guest:guest\@localhost:5672\/%2F@ using the @PLAIN@ SASL mechanism
--
--     * max frame size: @131072@
--
--     * use the heartbeat delay suggested by the broker
--
--     * no limit on the number of used channels
--
defaultConnectionOpts :: ConnectionOpts
defaultConnectionOpts = ConnectionOpts [("localhost", 5672)] "/" [plain "guest" "guest"] (Just 131072) Nothing Nothing Nothing

-- | @openConnection hostname virtualHost loginName loginPassword@ opens a connection to an AMQP server running on @hostname@.
-- @virtualHost@ is used as a namespace for AMQP resources (default is \"/\"), so different applications could use multiple virtual hosts on the same AMQP server.
--
-- You must call 'closeConnection' before your program exits to ensure that all published messages are received by the server.
--
-- The @loginName@ and @loginPassword@ will be used to authenticate via the 'PLAIN' SASL mechanism.
--
-- NOTE: If the login name, password or virtual host are invalid, this method will throw a 'ConnectionClosedException'. The exception will not contain a reason why the connection was closed, so you'll have to find out yourself.
openConnection :: String -> Text -> Text -> Text -> IO Connection
openConnection host = openConnection' host 5672

-- | same as 'openConnection' but allows you to specify a non-default port-number as the 2nd parameter
openConnection' :: String -> PortNumber -> Text -> Text -> Text -> IO Connection
openConnection' host port vhost loginName loginPassword = openConnection'' $ defaultConnectionOpts {
    coServers = [(host, port)],
    coVHost   = vhost,
    coAuth    = [plain loginName loginPassword]
}

-- | The @PLAIN@ SASL mechanism. See <http://tools.ietf.org/html/rfc4616 RFC4616>
plain :: Text -> Text -> SASLMechanism
plain loginName loginPassword = SASLMechanism "PLAIN" initialResponse Nothing
  where
    nul = '\0'
    initialResponse = E.encodeUtf8 $ (T.cons nul loginName) `T.append` (T.cons nul loginPassword)

-- | The @AMQPLAIN@ SASL mechanism. See <http://www.rabbitmq.com/authentication.html>.
amqplain :: Text -> Text -> SASLMechanism
amqplain loginName loginPassword = SASLMechanism "AMQPLAIN" initialResponse Nothing
  where
    initialResponse = toStrict $ BL.drop 4 $ runPut $ put $ FieldTable $ M.fromList [("LOGIN",FVString loginName), ("PASSWORD", FVString loginPassword)]

-- | The @RABBIT-CR-DEMO@ SASL mechanism needs to be explicitly enabled on the RabbitMQ server and should only be used for demonstration purposes of the challenge-response cycle.
-- See <http://www.rabbitmq.com/authentication.html>.
rabbitCRdemo :: Text -> Text -> SASLMechanism
rabbitCRdemo loginName loginPassword = SASLMechanism "RABBIT-CR-DEMO" initialResponse (Just $ const challengeResponse)
  where
    initialResponse = E.encodeUtf8 loginName
    challengeResponse = return $ (E.encodeUtf8 "My password is ") `BS.append` (E.encodeUtf8 loginPassword)

-- | @qos chan prefetchSize prefetchCount@ limits the amount of data the server
-- delivers before requiring acknowledgements. @prefetchSize@ specifies the
-- number of bytes and @prefetchCount@ the number of messages. In both cases
-- the value 0 means unlimited.
--
-- NOTE: RabbitMQ does not implement prefetchSize and will throw an exception if it doesn't equal 0.
qos :: Channel -> Word32 -> Word16 -> IO ()
qos chan prefetchSize prefetchCount = do
    (SimpleMethod Basic_qos_ok) <- request chan (SimpleMethod (Basic_qos
        prefetchSize
        prefetchCount
        False
        ))
    return ()

-- | Parses amqp standard URI of the form @amqp://user:password@host:port/vhost@ and returns a @ConnectionOpts@ for use with @openConnection''@
-- | Any of these fields may be empty and will be replaced with defaults from @amqp://guest:guest@localhost:5672/@
fromURI :: String -> ConnectionOpts
fromURI uri = defaultConnectionOpts {
    coServers = [(host,fromIntegral nport)],
    coVHost = (T.pack vhost),
    coAuth = [plain (T.pack uid) (T.pack pw)]
  }
  where (host,nport,uid,pw,vhost) = fromURI' uri

fromURI' :: String -> (String,Int,String,String,String)
fromURI' uri = (unEscapeString host, nport, unEscapeString (dropWhile (=='/') uid), unEscapeString pw, unEscapeString vhost)
  where (pre :suf  :    _) = splitOn "@" (uri ++ "@" ) -- look mom, no regexp dependencies
        (pro :uid' :pw':_) = splitOn ":" (pre ++ "::")
        (hnp :thost:    _) = splitOn "/" (suf ++ "/" )
        (hst':port :    _) = splitOn ":" (hnp ++ ":" )
        vhost = if null thost     then "/"     else thost
        dport = if pro == "amqps" then 5671    else 5672
        nport = if null port      then dport   else read port
        uid   = if null uid'      then "guest" else uid'
        pw    = if null pw'       then "guest" else pw'
        host  = if null hst'      then "localhost" else hst'

