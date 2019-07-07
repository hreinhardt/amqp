{-# LANGUAGE BangPatterns, CPP, OverloadedStrings, ScopedTypeVariables #-}
module Network.AMQP.Internal where

import Paths_amqp(version)
import Data.Version(showVersion)

import Control.Applicative
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad
import Data.Binary
import Data.Binary.Get
import Data.Binary.Put as BPut
import Data.Int (Int64)
import Data.Maybe
import Data.Text (Text)
import Network.Socket (PortNumber, withSocketsDo)
import System.IO (hPutStrLn, stderr)

import qualified Control.Exception as CE
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map as M
import qualified Data.Foldable as F
import qualified Data.IntMap as IM
import qualified Data.IntSet as IntSet
import qualified Data.Sequence as Seq
import qualified Data.Text as T
import qualified Data.Text.Encoding as E
import qualified Network.Connection as Conn

import Network.AMQP.Protocol
import Network.AMQP.Types
import Network.AMQP.Helpers
import Network.AMQP.Generated
import Network.AMQP.ChannelAllocator

data AckType = BasicAck | BasicNack deriving Show

data DeliveryMode = Persistent -- ^ the message will survive server restarts (if the queue is durable)
                  | NonPersistent -- ^ the message may be lost after server restarts
    deriving (Eq, Ord, Read, Show)

deliveryModeToInt :: DeliveryMode -> Octet
deliveryModeToInt NonPersistent = 1
deliveryModeToInt Persistent = 2

intToDeliveryMode :: Octet -> DeliveryMode
intToDeliveryMode 1 = NonPersistent
intToDeliveryMode 2 = Persistent
intToDeliveryMode n = error ("Unknown delivery mode int: " ++ show n)

-- | An AMQP message
data Message = Message {
                msgBody :: BL.ByteString, -- ^ the content of your message
                msgDeliveryMode :: Maybe DeliveryMode, -- ^ see 'DeliveryMode'
                msgTimestamp :: Maybe Timestamp, -- ^ use in any way you like; this doesn't affect the way the message is handled
                msgID :: Maybe Text, -- ^ use in any way you like; this doesn't affect the way the message is handled
                msgType :: Maybe Text, -- ^ use in any way you like; this doesn't affect the way the message is handled
                msgUserID :: Maybe Text,
                msgApplicationID :: Maybe Text,
                msgClusterID :: Maybe Text,
                msgContentType :: Maybe Text,
                msgContentEncoding :: Maybe Text,
                msgReplyTo :: Maybe Text,
                msgPriority :: Maybe Octet,
                msgCorrelationID :: Maybe Text,
                msgExpiration :: Maybe Text,
                msgHeaders :: Maybe FieldTable
                }
    deriving (Eq, Ord, Read, Show)

-- | contains meta-information of a delivered message (through 'getMsg' or 'consumeMsgs')
data Envelope = Envelope
              {
                envDeliveryTag :: LongLongInt,
                envRedelivered :: Bool,
                envExchangeName :: Text,
                envRoutingKey :: Text,
                envChannel :: Channel
              }

data PublishError = PublishError
                  {
                    errReplyCode :: ReturnReplyCode,
                    errExchange :: Maybe Text,
                    errRoutingKey :: Text
                  }
    deriving (Eq, Read, Show)

data ReturnReplyCode = Unroutable Text
                     | NoConsumers Text
                     | NotFound Text
    deriving (Eq, Read, Show)

------------- ASSEMBLY -------------------------
-- an assembly is a higher-level object consisting of several frames (like in amqp 0-10)
data Assembly = SimpleMethod MethodPayload
              | ContentMethod MethodPayload ContentHeaderProperties BL.ByteString --method, properties, content-data
    deriving Show

-- | reads all frames necessary to build an assembly
readAssembly :: Chan FramePayload -> IO Assembly
readAssembly chan = do
    m <- readChan chan
    case m of
        MethodPayload p -> --got a method frame
            if hasContent m
                then do
                    --several frames containing the content will follow, so read them
                    (props, msg) <- collectContent chan
                    return $ ContentMethod p props msg
                else do
                    return $ SimpleMethod p
        x -> error $ "didn't expect frame: " ++ show x

-- | reads a contentheader and contentbodies and assembles them
collectContent :: Chan FramePayload -> IO (ContentHeaderProperties, BL.ByteString)
collectContent chan = do
    (ContentHeaderPayload _ _ bodySize props) <- readChan chan

    content <- collect $ fromIntegral bodySize
    return (props, BL.concat content)
  where
    collect x | x <= 0 = return []
    collect x = do
        (ContentBodyPayload payload) <- readChan chan
        r <- collect (x - (BL.length payload))
        return $ payload : r

------------ CONNECTION -------------------

{- general concept:
Each connection has its own thread. Each channel has its own thread.
Connection reads data from socket and forwards it to channel. Channel processes data and forwards it to application.
Outgoing data is written directly onto the socket.

Incoming Data: Socket -> Connection-Thread -> Channel-Thread -> Application
Outgoing Data: Application -> Socket
-}

data Connection = Connection {
                    connHandle :: Conn.Connection,
                    connChanAllocator :: ChannelAllocator,
                    connChannels :: MVar (IM.IntMap (Channel, ThreadId)), -- open channels (channelID => (Channel, ChannelThread))
                    connMaxFrameSize :: Int, --negotiated maximum frame size
                    connClosed :: MVar (Maybe (CloseType, String)),
                    connClosedLock :: MVar (), -- used by closeConnection to block until connection-close handshake is complete
                    connWriteLock :: MVar (), -- to ensure atomic writes to the socket
                    connClosedHandlers :: MVar [IO ()],
                    connBlockedHandlers :: MVar [(Text -> IO (), IO ())],
                    connLastReceived :: MVar Int64, -- the timestamp from a monotonic clock when the last frame was received
                    connLastSent :: MVar Int64, -- the timestamp from a monotonic clock when the last frame was written
                    connServerProperties :: FieldTable -- the server properties sent in Connection_start
                }

-- | Represents the parameters to connect to a broker or a cluster of brokers.
-- See 'defaultConnectionOpts'.
data ConnectionOpts = ConnectionOpts {
                            coServers :: ![(String, PortNumber)], -- ^ A list of host-port pairs. Useful in a clustered setup to connect to the first available host.
                            coVHost :: !Text, -- ^ The VHost to connect to.
                            coAuth :: ![SASLMechanism], -- ^ The 'SASLMechanism's to use for authenticating with the broker.
                            coMaxFrameSize :: !(Maybe Word32), -- ^ The maximum frame size to be used. If not specified, no limit is assumed.
                            coHeartbeatDelay :: !(Maybe Word16), -- ^ The delay in seconds, after which the client expects a heartbeat frame from the broker. If 'Nothing', the value suggested by the broker is used. Use @Just 0@ to disable the heartbeat mechnism.
                            coMaxChannel :: !(Maybe Word16), -- ^ The maximum number of channels the client will use.
                            coTLSSettings :: Maybe TLSSettings, -- ^ Whether or not to connect to servers using TLS. See http://www.rabbitmq.com/ssl.html for details.
                            coName :: !(Maybe Text) -- ^ optional connection name (will be displayed in the RabbitMQ web interface)
                        }
-- | Represents the kind of TLS connection to establish.
data TLSSettings =
    TLSTrusted   -- ^ Require trusted certificates (Recommended).
  | TLSUntrusted -- ^ Allow untrusted certificates (Discouraged. Vulnerable to man-in-the-middle attacks)
  | TLSCustom Conn.TLSSettings -- ^ Provide your own custom TLS settings

connectionTLSSettings :: TLSSettings -> Maybe Conn.TLSSettings
connectionTLSSettings tlsSettings =
  Just $ case tlsSettings of
    TLSTrusted -> Conn.TLSSettingsSimple False False False
    TLSUntrusted -> Conn.TLSSettingsSimple True False False
    TLSCustom x -> x

-- | A 'SASLMechanism' is described by its name ('saslName'), its initial response ('saslInitialResponse'), and an optional function ('saslChallengeFunc') that
-- transforms a security challenge provided by the server into response, which is then sent back to the server for verification.
data SASLMechanism = SASLMechanism {
                        saslName :: !Text, -- ^ mechanism name
                        saslInitialResponse :: !BS.ByteString, -- ^ initial response
                        saslChallengeFunc :: !(Maybe (BS.ByteString -> IO BS.ByteString)) -- ^ challenge processing function
                    }

-- | reads incoming frames from socket and forwards them to the opened channels
connectionReceiver :: Connection -> IO ()
connectionReceiver conn = do
    CE.catch (do
        Frame chanID payload <- readFrame (connHandle conn)
        updateLastReceived conn
        forwardToChannel chanID payload
        )
        (\(e :: CE.IOException) -> myThreadId >>= killConnection conn Abnormal (CE.toException e))
    connectionReceiver conn
  where

    closedByUserEx = ConnectionClosedException Normal "closed by user"

    forwardToChannel 0 (MethodPayload Connection_close_ok) =  myThreadId >>= killConnection conn Normal (CE.toException closedByUserEx)
    forwardToChannel 0 (MethodPayload (Connection_close _ (ShortString errorMsg) _ _)) = do
        writeFrame (connHandle conn) $ Frame 0 $ MethodPayload Connection_close_ok
        myThreadId >>= killConnection conn Abnormal (CE.toException . ConnectionClosedException Abnormal . T.unpack $ errorMsg)
    forwardToChannel 0 HeartbeatPayload = return ()
    forwardToChannel 0 (MethodPayload (Connection_blocked reason)) = handleBlocked reason
    forwardToChannel 0 (MethodPayload Connection_unblocked) = handleUnblocked
    forwardToChannel 0 payload = hPutStrLn stderr $ "Got unexpected msg on channel zero: " ++ show payload
    forwardToChannel chanID payload = do
        --got asynchronous msg => forward to registered channel
        withMVar (connChannels conn) $ \cs -> do
            case IM.lookup (fromIntegral chanID) cs of
                Just c -> writeChan (inQueue $ fst c) payload
                Nothing -> hPutStrLn stderr $ "ERROR: channel not open " ++ show chanID

    handleBlocked (ShortString reason) = do
        withMVar (connBlockedHandlers conn) $ \listeners ->
            forM_ listeners $ \(l, _) -> CE.catch (l reason) $ \(ex :: CE.SomeException) ->
                hPutStrLn stderr $ "connection blocked listener threw exception: "++ show ex

    handleUnblocked = do
        withMVar (connBlockedHandlers conn) $ \listeners ->
            forM_ listeners $ \(_, l) -> CE.catch l $ \(ex :: CE.SomeException) ->
                hPutStrLn stderr $ "connection unblocked listener threw exception: "++ show ex

-- | Opens a connection to a broker specified by the given 'ConnectionOpts' parameter.
openConnection'' :: ConnectionOpts -> IO Connection
openConnection'' connOpts = withSocketsDo $ do
    handle <- connect [] $ coServers connOpts
    (maxFrameSize, maxChannel, heartbeatTimeout, serverProps) <- CE.handle (\(_ :: CE.IOException) -> CE.throwIO $ ConnectionClosedException Abnormal "Handshake failed. Please check the RabbitMQ logs for more information") $ do
        Conn.connectionPut handle $ BS.append (BC.pack "AMQP")
                (BS.pack [
                          1
                        , 1 --TCP/IP
                        , 0 --Major Version
                        , 9 --Minor Version
                       ])

        -- S: connection.start
        Frame 0 (MethodPayload (Connection_start _ _ serverProps (LongString serverMechanisms) _)) <- readFrame handle
        selectedSASL <- selectSASLMechanism handle serverMechanisms

        -- C: start_ok
        writeFrame handle $ start_ok selectedSASL
        -- S: secure or tune
        Frame 0 (MethodPayload (Connection_tune channel_max frame_max sendHeartbeat)) <- handleSecureUntilTune handle selectedSASL
        -- C: tune_ok
        let maxFrameSize = chooseMin frame_max $ coMaxFrameSize connOpts
            finalHeartbeatSec = fromMaybe sendHeartbeat (coHeartbeatDelay connOpts)
            heartbeatTimeout = mfilter (/=0) (Just finalHeartbeatSec)

            fixChanNum x = if x == 0 then 65535 else x
            maxChannel = chooseMin (fixChanNum channel_max) $ fmap fixChanNum $ coMaxChannel connOpts

        writeFrame handle (Frame 0 (MethodPayload
            (Connection_tune_ok maxChannel maxFrameSize finalHeartbeatSec)
            ))
        -- C: open
        writeFrame handle open

        -- S: open_ok
        Frame 0 (MethodPayload (Connection_open_ok _)) <- readFrame handle

        -- Connection established!
        return (maxFrameSize, maxChannel, heartbeatTimeout, serverProps)

    --build Connection object
    cChannels <- newMVar IM.empty
    cClosed <- newMVar Nothing
    cChanAllocator <- newChannelAllocator $ fromIntegral maxChannel
    _ <- allocateChannel cChanAllocator -- allocate channel 0
    writeLock <- newMVar ()
    ccl <- newEmptyMVar
    cClosedHandlers <- newMVar []
    cBlockedHandlers <- newMVar []
    cLastReceived <- getTimestamp >>= newMVar
    cLastSent <- getTimestamp >>= newMVar
    let conn = Connection handle cChanAllocator cChannels (fromIntegral maxFrameSize) cClosed ccl writeLock cClosedHandlers cBlockedHandlers cLastReceived cLastSent serverProps

    --spawn the connectionReceiver
    connThread <- forkFinally' (connectionReceiver conn) $ \res -> do
                -- try closing socket
                CE.catch (Conn.connectionClose handle) (\(_ :: CE.SomeException) -> return ())

                -- mark as closed
                modifyMVar_ cClosed $ return . Just . fromMaybe (Abnormal, "unknown reason")

                -- kill all channel-threads, making sure the channel threads will
                -- be killed taking into account the overall state of the
                -- connection: if the thread died for an unexpected exception,
                -- inform the channel threads downstream accordingly. Otherwise
                -- just use a normal 'killThread' finaliser.
                let finaliser = ChanThreadKilledException $ case res of
                        Left ex -> ex
                        Right _ -> CE.toException CE.ThreadKilled
                modifyMVar_ cChannels $ \x -> do
                    mapM_ (flip CE.throwTo finaliser . snd) $ IM.elems x
                    return IM.empty

                -- mark connection as closed, so all pending calls to 'closeConnection' can now return
                void $ tryPutMVar ccl ()

                -- notify connection-close-handlers
                withMVar cClosedHandlers sequence_

    case heartbeatTimeout of
        Nothing      -> return ()
        Just timeout ->  do
            heartbeatThread <- watchHeartbeats conn (fromIntegral timeout) connThread
            addConnectionClosedHandler conn True (killThread heartbeatThread)

    return conn
  where
    connect excs ((host, port) : rest) = do
        ctx <- Conn.initConnectionContext
        result <- CE.try (Conn.connectTo ctx $ Conn.ConnectionParams
                              { Conn.connectionHostname  = host
                              , Conn.connectionPort      = port
                              , Conn.connectionUseSecure = tlsSettings
                              , Conn.connectionUseSocks  = Nothing
                              })
        either
            (\(ex :: CE.SomeException) -> do
                connect (ex:excs) rest)
            (return)
            result
    connect excs [] = CE.throwIO $ ConnectionClosedException Abnormal $ "Could not connect to any of the provided brokers: " ++ show (zip (coServers connOpts) (reverse excs))
    tlsSettings = maybe Nothing connectionTLSSettings (coTLSSettings connOpts)
    selectSASLMechanism handle serverMechanisms =
        let serverSaslList = T.split (== ' ') $ E.decodeUtf8 serverMechanisms
            clientMechanisms = coAuth connOpts
            clientSaslList = map saslName clientMechanisms
            maybeSasl = F.find (\(SASLMechanism name _ _) -> elem name serverSaslList) clientMechanisms
        in abortIfNothing maybeSasl handle
            ("None of the provided SASL mechanisms "++show clientSaslList++" is supported by the server "++show serverSaslList++".")

    start_ok sasl = (Frame 0 (MethodPayload (Connection_start_ok clientProperties
                                             (ShortString $ saslName sasl)
                                             (LongString $ saslInitialResponse sasl)
                                             (ShortString "en_US")) ))
                    where clientProperties = FieldTable $ M.fromList $ [ ("platform", FVString "Haskell")
                                                                       , ("version" , FVString . T.pack $ showVersion version)
                                                                       , ("capabilities", FVFieldTable clientCapabilities)
                                                                       ] ++ maybe [] (\x -> [("connection_name", FVString x)]) (coName connOpts)

                          clientCapabilities = FieldTable $ M.fromList $ [ ("consumer_cancel_notify", FVBool True),
                                                                           ("connection.blocked", FVBool True) ]

    handleSecureUntilTune handle sasl = do
        tuneOrSecure <- readFrame handle
        case tuneOrSecure of
            Frame 0 (MethodPayload (Connection_secure (LongString challenge))) -> do
                processChallenge <- abortIfNothing (saslChallengeFunc sasl)
                    handle $ "The server provided a challenge, but the selected SASL mechanism "++show (saslName sasl)++" is not equipped with a challenge processing function."
                challengeResponse <- processChallenge challenge
                writeFrame handle (Frame 0 (MethodPayload (Connection_secure_ok (LongString challengeResponse))))
                handleSecureUntilTune handle sasl

            tune@(Frame 0 (MethodPayload (Connection_tune _ _ _))) -> return tune
            x -> error $ "handleSecureUntilTune fail. received message: "++show x

    open = (Frame 0 (MethodPayload (Connection_open
        (ShortString $ coVHost connOpts)
        (ShortString $ T.pack "") -- capabilities; deprecated in 0-9-1
        True))) -- insist; deprecated in 0-9-1

    abortHandshake handle msg = do
        Conn.connectionClose handle
        CE.throwIO $ ConnectionClosedException Abnormal msg

    abortIfNothing m handle msg = case m of
        Nothing -> abortHandshake handle msg
        Just a  -> return a


watchHeartbeats :: Connection -> Int -> ThreadId -> IO ThreadId
watchHeartbeats conn timeout connThread = scheduleAtFixedRate rate $ do
    checkSendTimeout
    checkReceiveTimeout
  where
    rate = timeout * 1000 * 250 -- timeout / 4 in µs
    receiveTimeout = (fromIntegral rate) * 4 * 2 -- 2*timeout in µs
    sendTimeout = (fromIntegral rate) * 2 -- timeout/2 in µs

    skippedBeatEx = ConnectionClosedException Abnormal "killed connection after missing 2 consecutive heartbeats"

    checkReceiveTimeout = doCheck (connLastReceived conn) receiveTimeout
        (killConnection conn Abnormal (CE.toException skippedBeatEx) connThread)

    checkSendTimeout = doCheck (connLastSent conn) sendTimeout
        (writeFrame (connHandle conn) (Frame 0 HeartbeatPayload))

    doCheck var timeout_µs action = withMVar var $ \lastFrameTime -> do
        time <- getTimestamp
        when (time >= lastFrameTime + timeout_µs) $ do
            action

updateLastSent :: Connection -> IO ()
updateLastSent conn = modifyMVar_ (connLastSent conn) (const getTimestamp)

updateLastReceived :: Connection -> IO ()
updateLastReceived conn = modifyMVar_ (connLastReceived conn) (const getTimestamp)

-- | kill the connection thread abruptly
killConnection :: Connection -> CloseType -> CE.SomeException -> ThreadId -> IO ()
killConnection conn closeType ex connThread = do
    modifyMVar_ (connClosed conn) $ const $ return $ Just (closeType, show ex)
    throwTo connThread ex

-- | closes a connection
--
-- Make sure to call this function before your program exits to ensure that all published messages are received by the server.
closeConnection :: Connection -> IO ()
closeConnection c = do
    CE.catch (
        withMVar (connWriteLock c) $ \_ -> writeFrame (connHandle c) $ (Frame 0 (MethodPayload (Connection_close
            --TODO: set these values
            0 -- reply_code
            (ShortString "") -- reply_text
            0 -- class_id
            0 -- method_id
            )))
            )
        (\ (_ :: CE.IOException) ->
            --do nothing if connection is already closed
            return ()
        )

    -- wait for connection_close_ok by the server; this MVar gets filled in the CE.finally handler in openConnection'
    readMVar $ connClosedLock c
    return ()

-- | get the server properties sent in connection.start
getServerProperties :: Connection -> IO FieldTable
getServerProperties = return . connServerProperties

-- | @addConnectionClosedHandler conn ifClosed handler@ adds a @handler@ that will be called after the connection is closed (either by calling @closeConnection@ or by an exception). If the @ifClosed@ parameter is True and the connection is already closed, the handler will be called immediately. If @ifClosed == False@ and the connection is already closed, the handler will never be called
addConnectionClosedHandler :: Connection -> Bool -> IO () -> IO ()
addConnectionClosedHandler conn ifClosed handler = do
    withMVar (connClosed conn) $ \cc ->
        case cc of
            -- connection is already closed, so call the handler directly
            Just _ | ifClosed == True -> handler

            -- otherwise add it to the list
            _ -> modifyMVar_ (connClosedHandlers conn) $ \old -> return $ handler:old

-- | @addConnectionBlockedHandler conn blockedHandler unblockedHandler@ adds handlers that will be called
-- when a connection gets blocked/unlocked due to server resource constraints.
--
-- More information: <https://www.rabbitmq.com/connection-blocked.html>
addConnectionBlockedHandler :: Connection -> (Text -> IO ()) -> IO () -> IO ()
addConnectionBlockedHandler conn blockedHandler unblockedHandler =
    modifyMVar_ (connBlockedHandlers conn) $ \old -> return $ (blockedHandler, unblockedHandler):old

readFrame :: Conn.Connection -> IO Frame
readFrame handle = do
    strictDat <- connectionGetExact handle 7
    let dat = toLazy strictDat
    -- NB: userError returns an IOException so it will be catched in 'connectionReceiver'
    when (BL.null dat) $ CE.throwIO $ userError "connection not open"
    let len = fromIntegral $ peekFrameSize dat
    strictDat' <- connectionGetExact handle (len+1) -- +1 for the terminating 0xCE
    let dat' = toLazy strictDat'
    when (BL.null dat') $ CE.throwIO $ userError "connection not open"
#if MIN_VERSION_binary(0, 7, 0)
    let ret = runGetOrFail get (BL.append dat dat')
    case ret of
        Left (_, _, errMsg) -> error $ "readFrame fail: " ++ errMsg
        Right (_, consumedBytes, _) | consumedBytes /= fromIntegral (len+8) ->
            error $ "readFrame: parser should read " ++ show (len+8) ++ " bytes; but read " ++ show consumedBytes
        Right (_, _, frame) -> return frame
#else
    let (frame, _, consumedBytes) = runGetState get (BL.append dat dat') 0
    if consumedBytes /= fromIntegral (len+8)
        then error $ "readFrameSock: parser should read "++show (len+8)++" bytes; but read "++show consumedBytes
        else return ()
    return frame
#endif

-- belongs in connection package and will be removed once it lands there
connectionGetExact :: Conn.Connection -> Int -> IO BS.ByteString
connectionGetExact conn x = loop BS.empty 0
  where loop bs y
          | y == x = return bs
          | otherwise = do
            next <- Conn.connectionGet conn (x - y)
            loop (BS.append bs next) (y + (BS.length next))

writeFrame :: Conn.Connection -> Frame -> IO ()
writeFrame handle f = do
    Conn.connectionPut handle . toStrict . runPut . put $ f

------------------------ CHANNEL -----------------------------

{- | A connection to an AMQP server is made up of separate channels. It is recommended to use a separate channel for each thread in your application that talks to the AMQP server (but you don't have to as channels are thread-safe)
-}
data Channel = Channel {
                    connection :: Connection,
                    inQueue :: Chan FramePayload, --incoming frames (from Connection)
                    outstandingResponses :: MVar (Seq.Seq (MVar Assembly)), -- for every request an MVar is stored here waiting for the response
                    channelID :: Word16,
                    lastConsumerTag :: MVar Int,

                    nextPublishSeqNum :: MVar Int,
                    unconfirmedSet :: TVar IntSet.IntSet,
                    ackedSet :: TVar IntSet.IntSet,  --delivery tags
                    nackedSet :: TVar IntSet.IntSet, --accumulate here.

                    chanActive :: Lock, -- used for flow-control. if lock is closed, no content methods will be sent
                    chanClosed :: MVar (Maybe (CloseType, String)),
                    consumers :: MVar (M.Map Text ((Message, Envelope) -> IO (),    -- who is consumer of a queue? (consumerTag => callback)
                                                   (ConsumerTag -> IO ()))),        -- cancellation notification callback
                    returnListeners :: MVar ([(Message, PublishError) -> IO ()]),
                    confirmListeners :: MVar ([(Word64, Bool, AckType) -> IO ()]),
                    chanExceptionHandlers :: MVar [CE.SomeException -> IO ()]
                }

-- | Thrown in the channel thread when the connection gets closed.
-- When handling exceptions in a subscription callback, make sure to re-throw this so the channel thread can be stopped.
data ChanThreadKilledException = ChanThreadKilledException { cause :: CE.SomeException }
  deriving (Show)

instance CE.Exception ChanThreadKilledException

unwrapChanThreadKilledException :: CE.SomeException -> CE.SomeException
unwrapChanThreadKilledException e = maybe e cause $ CE.fromException e

msgFromContentHeaderProperties :: ContentHeaderProperties -> BL.ByteString -> Message
msgFromContentHeaderProperties (CHBasic content_type content_encoding headers delivery_mode priority correlation_id reply_to expiration message_id timestamp message_type user_id application_id cluster_id) body =
    let msgId = fromShortString message_id
        contentType = fromShortString content_type
        contentEncoding = fromShortString content_encoding
        replyTo = fromShortString reply_to
        correlationID = fromShortString correlation_id
        messageType = fromShortString message_type
        userId = fromShortString user_id
        applicationId = fromShortString application_id
        clusterId = fromShortString cluster_id
    in Message body (fmap intToDeliveryMode delivery_mode) timestamp msgId messageType userId applicationId clusterId contentType contentEncoding replyTo priority correlationID (fromShortString expiration) headers
  where
    fromShortString (Just (ShortString s)) = Just s
    fromShortString _ = Nothing
msgFromContentHeaderProperties c _ = error ("Unknown content header properties: " ++ show c)

-- | The thread that is run for every channel
channelReceiver :: Channel -> IO ()
channelReceiver chan = do
    --read incoming frames; they are put there by a Connection thread
    p <- readAssembly $ inQueue chan
    if isResponse p
        then do
            action <- modifyMVar (outstandingResponses chan) $ \val -> do
                        case Seq.viewl val of
                            x Seq.:< rest -> do
                                return (rest, putMVar x p)
                            Seq.EmptyL -> do
                                return (val, CE.throwIO $ userError "got response, but have no corresponding request")
            action

        --handle asynchronous assemblies
        else handleAsync p
    channelReceiver chan
  where
    isResponse :: Assembly -> Bool
    isResponse (ContentMethod (Basic_deliver _ _ _ _ _) _ _) = False
    isResponse (ContentMethod (Basic_return _ _ _ _) _ _) = False
    isResponse (SimpleMethod (Channel_flow _)) = False
    isResponse (SimpleMethod (Channel_close _ _ _ _)) = False
    isResponse (SimpleMethod (Basic_ack _ _)) = False
    isResponse (SimpleMethod (Basic_nack _ _ _)) = False
    isResponse (SimpleMethod (Basic_cancel _ _)) = False
    isResponse _ = True

    --Basic.Deliver: forward msg to registered consumer
    handleAsync (ContentMethod (Basic_deliver (ShortString consumerTag) deliveryTag redelivered (ShortString exchange)
                                                (ShortString routingKey))
                                properties body) =
        withMVar (consumers chan) (\s -> do
            case M.lookup consumerTag s of
                Just (subscriber, _) -> do
                    let msg = msgFromContentHeaderProperties properties body
                    let env = Envelope {envDeliveryTag = deliveryTag, envRedelivered = redelivered,
                                    envExchangeName = exchange, envRoutingKey = routingKey, envChannel = chan}

                    CE.catches (subscriber (msg, env))
                        [
                          CE.Handler (\(e::ChanThreadKilledException) -> CE.throwIO $ cause e),
                          CE.Handler (\(e::CE.SomeException) -> hPutStrLn stderr $ "AMQP callback threw exception: " ++ show e)
                        ]
                Nothing ->
                    -- got a message, but have no registered subscriber; so drop it
                    return ()
            )
    handleAsync (SimpleMethod (Channel_close _ (ShortString errorMsg) _ _)) = do
      CE.catch (
        writeAssembly' chan (SimpleMethod (Channel_close_ok))
        )
        (\ (_ :: CE.IOException) ->
              --do nothing if connection is already closed
              return ()
        )
      closeChannel' chan Abnormal errorMsg
      myThreadId >>= flip CE.throwTo (ChannelClosedException Abnormal . T.unpack $ errorMsg)
    handleAsync (SimpleMethod (Channel_flow active)) = do
        if active
            then openLock $ chanActive chan
            else closeLock $ chanActive chan
        -- in theory we should respond with flow_ok but rabbitMQ 1.7 ignores that, so it doesn't matter
        return ()
    --Basic.return
    handleAsync (ContentMethod basicReturn@(Basic_return _ _ _ _) props body) = do
        let msg      = msgFromContentHeaderProperties props body
            pubError = basicReturnToPublishError basicReturn
        withMVar (returnListeners chan) $ \listeners ->
            forM_ listeners $ \l -> CE.catch (l (msg, pubError)) $ \(ex :: CE.SomeException) ->
                hPutStrLn stderr $ "return listener on channel ["++(show $ channelID chan)++"] handling error ["++show pubError++"] threw exception: "++show ex
    handleAsync (SimpleMethod (Basic_ack deliveryTag multiple)) = handleConfirm deliveryTag multiple BasicAck
    handleAsync (SimpleMethod (Basic_nack deliveryTag multiple _)) = handleConfirm deliveryTag multiple BasicNack
    handleAsync (SimpleMethod (Basic_cancel consumerTag _)) = handleCancel consumerTag
    handleAsync m = error ("Unknown method: " ++ show m)

    handleConfirm deliveryTag multiple k = do
        withMVar (confirmListeners chan) $ \listeners ->
            forM_ listeners $ \l -> CE.catch (l (deliveryTag, multiple, k)) $ \(ex :: CE.SomeException) ->
                hPutStrLn stderr $ "confirm listener on channel ["++(show $ channelID chan)++"] handling method "++(show k)++" threw exception: "++ show ex

        let seqNum = fromIntegral deliveryTag
        let targetSet = case k of
              BasicAck  -> (ackedSet chan)
              BasicNack -> (nackedSet chan)
        atomically $ do
          unconfSet <- readTVar (unconfirmedSet chan)
          let (merge, pending) = if multiple
                                     then (IntSet.union confs, pending')
                                     else (IntSet.insert seqNum, IntSet.delete seqNum unconfSet)
                                  where
                                    confs = fst parts
                                    pending' = snd parts
                                    parts = IntSet.partition (\n -> n <= seqNum) unconfSet
          modifyTVar' targetSet (\ts -> merge ts)
          writeTVar (unconfirmedSet chan) pending

    handleCancel (ShortString consumerTag) =
        withMVar (consumers chan) (\s -> do
            case M.lookup consumerTag s of
                Just (_, cancelCB) ->
                    CE.catch (cancelCB consumerTag) $ \(ex :: CE.SomeException) ->
                        hPutStrLn stderr $ "consumer cancellation listener "++(show consumerTag)++" on channel ["++(show $ channelID chan)++"] threw exception: "++ show ex
                Nothing ->
                    -- got a cancellation notification, but have no registered subscriber; so drop it
                    return ()
            )

    basicReturnToPublishError (Basic_return code (ShortString errText) (ShortString exchange) (ShortString routingKey)) =
        let replyError = case code of
                312 -> Unroutable errText
                313 -> NoConsumers errText
                404 -> NotFound errText
                num -> error $ "unexpected return error code: " ++ (show num)
            pubError = PublishError replyError (Just exchange) routingKey
        in pubError
    basicReturnToPublishError x = error $ "basicReturnToPublishError fail: "++show x

-- | registers a callback function that is called whenever a message is returned from the broker ('basic.return').
addReturnListener :: Channel -> ((Message, PublishError) -> IO ()) -> IO ()
addReturnListener chan listener = do
    modifyMVar_ (returnListeners chan) $ \listeners -> return $ listener:listeners

-- | registers a callback function that is called whenever a channel is closed by an exception.
addChannelExceptionHandler :: Channel -> (CE.SomeException -> IO ()) -> IO ()
addChannelExceptionHandler chan handler = do
    modifyMVar_ (chanExceptionHandlers chan) $ \handlers -> return $ handler:handlers

-- closes the channel internally; but doesn't tell the server
closeChannel' :: Channel -> CloseType -> Text -> IO ()
closeChannel' c closeType reason = do
    modifyMVar_ (chanClosed c) $ \x -> do
        if isNothing x
            then do
                modifyMVar_ (connChannels $ connection c) $ \old -> do
                    ret <- freeChannel (connChanAllocator $ connection c) $ fromIntegral $ channelID c
                    when (not ret) $ hPutStrLn stderr "closeChannel error: channel already freed"
                    return $ IM.delete (fromIntegral $ channelID c) old

                void $ killLock $ chanActive c
                killOutstandingResponses $ outstandingResponses c
                return $ Just (closeType, T.unpack reason)
            else return x
  where
    killOutstandingResponses :: MVar (Seq.Seq (MVar a)) -> IO ()
    killOutstandingResponses outResps = do
        modifyMVar_ outResps $ \val -> do
            F.mapM_ (\x -> tryPutMVar x $ error "channel closed") val
            return undefined

-- | opens a new channel on the connection
--
-- By default, if a channel is closed by an AMQP exception, this exception will be printed to stderr. You can prevent this behaviour by setting a custom exception handler (using 'addChannelExceptionHandler').
openChannel :: Connection -> IO Channel
openChannel c = do
    newInQueue <- newChan
    outRes <- newMVar Seq.empty
    lastConsTag <- newMVar 0
    ca <- newLock
    closed <- newMVar Nothing
    conss <- newMVar M.empty
    retListeners <- newMVar []
    aSet <- newTVarIO IntSet.empty
    nSet <- newTVarIO IntSet.empty
    nxtSeq <- newMVar 0
    unconfSet <- newTVarIO IntSet.empty
    cnfListeners <- newMVar []
    handlers <- newMVar []

    --add new channel to connection's channel map
    newChannel <- modifyMVar (connChannels c) $ \mp -> do
        newChannelID <- allocateChannel (connChanAllocator c)
        let newChannel = Channel c newInQueue outRes (fromIntegral newChannelID) lastConsTag nxtSeq unconfSet aSet nSet ca closed conss retListeners cnfListeners handlers
        thrID <- forkFinally' (channelReceiver newChannel) $ \res -> do
                   closeChannel' newChannel Normal "closed"
                   case res of
                     Right _ -> return ()
                     Left ex -> do
                        let unwrappedExc = unwrapChanThreadKilledException ex
                        handlers' <- readMVar handlers

                        case (null handlers', fromAbnormalChannelClose unwrappedExc) of
                            (True, Just reason) -> hPutStrLn stderr $ "unhandled AMQP channel exception (chanId="++show newChannelID++"): "++reason
                            _ -> mapM_ ($ unwrappedExc) handlers'
        when (IM.member newChannelID mp) $ CE.throwIO $ userError "openChannel fail: channel already open"
        return (IM.insert newChannelID (newChannel, thrID) mp, newChannel)

    SimpleMethod (Channel_open_ok _) <- request newChannel (SimpleMethod (Channel_open (ShortString "")))
    return newChannel

  where
    fromAbnormalChannelClose :: CE.SomeException -> Maybe String
    fromAbnormalChannelClose exc =
        case CE.fromException exc :: Maybe AMQPException of
            Just (ChannelClosedException Abnormal reason) -> Just reason
            _ -> Nothing

-- | closes a channel. It is typically not necessary to manually call this as closing a connection will implicitly close all channels.
closeChannel :: Channel -> IO ()
closeChannel c = do
    SimpleMethod Channel_close_ok <- request c $ SimpleMethod $ Channel_close 0 (ShortString "") 0 0
    withMVar (connChannels $ connection c) $ \chans -> do
        case IM.lookup (fromIntegral $ channelID c) chans of
            Just (_, thrID) -> killThread thrID
            Nothing -> return ()

-- | writes multiple frames to the channel atomically
writeFrames :: Channel -> [FramePayload] -> IO ()
writeFrames chan payloads =
    let conn = connection chan in
        withMVar (connChannels conn) $ \chans ->
            if IM.member (fromIntegral $ channelID chan) chans
                then
                    CE.catch
                        -- ensure at most one thread is writing to the socket at any time
                        (do
                            withMVar (connWriteLock conn) $ \_ ->
                                mapM_ (\payload -> writeFrame (connHandle conn) (Frame (channelID chan) payload)) payloads
                            updateLastSent conn)
                        ( \(_ :: CE.IOException) -> do
                            CE.throwIO $ userError "connection not open"
                        )
                else do
                    CE.throwIO $ userError "channel not open"

writeAssembly' :: Channel -> Assembly -> IO ()
writeAssembly' chan (ContentMethod m properties msg) = do
    -- wait iff the AMQP server instructed us to withhold sending content data (flow control)
    waitLock $ chanActive chan
    let !toWrite =
           [(MethodPayload m),
            (ContentHeaderPayload
                (getClassIDOf properties) --classID
                0 --weight is deprecated in AMQP 0-9
                (fromIntegral $ BL.length msg) --bodySize
                properties)] ++
            (if BL.length msg > 0
             then do
                -- split into frames of maxFrameSize
                -- (need to substract 8 bytes to account for frame header and end-marker)
                map ContentBodyPayload
                    (splitLen msg $ (fromIntegral $ connMaxFrameSize $ connection chan) - 8)
             else []
            )
    writeFrames chan toWrite
  where
    splitLen str len | BL.length str > len = (BL.take len str):(splitLen (BL.drop len str) len)
    splitLen str _ = [str]
writeAssembly' chan (SimpleMethod m) = writeFrames chan [MethodPayload m]

-- most exported functions in this module will use either 'writeAssembly' or 'request' to talk to the server
-- so we perform the exception handling here

-- | writes an assembly to the channel
writeAssembly :: Channel -> Assembly -> IO ()
writeAssembly chan m =
    CE.catches
        (writeAssembly' chan m)
        [CE.Handler (\ (_ :: AMQPException) -> throwMostRelevantAMQPException chan),
         CE.Handler (\ (_ :: CE.ErrorCall) -> throwMostRelevantAMQPException chan),
         CE.Handler (\ (_ :: CE.IOException) -> throwMostRelevantAMQPException chan)]

-- | sends an assembly and receives the response
request :: Channel -> Assembly -> IO Assembly
request chan m = do
    res <- newEmptyMVar
    CE.catches (do
            withMVar (chanClosed chan) $ \cc -> do
                if isNothing cc
                    then do
                        modifyMVar_ (outstandingResponses chan) $ \val -> return $! val Seq.|> res
                        writeAssembly' chan m
                    else CE.throwIO $ userError "closed"

            -- res might contain an exception, so evaluate it here
            !r <- takeMVar res
            return r
            )
        [CE.Handler (\ (_ :: AMQPException) -> throwMostRelevantAMQPException chan),
         CE.Handler (\ (_ :: CE.ErrorCall) -> throwMostRelevantAMQPException chan),
         CE.Handler (\ (_ :: CE.IOException) -> throwMostRelevantAMQPException chan)]

-- this throws an AMQPException based on the status of the connection and the channel
-- if both connection and channel are closed, it will throw a ConnectionClosedException
throwMostRelevantAMQPException :: Channel -> IO a
throwMostRelevantAMQPException chan = do
    cc <- readMVar $ connClosed $ connection chan
    case cc of
        Just (closeType, r) -> CE.throwIO $ ConnectionClosedException closeType r
        Nothing -> do
            chc <- readMVar $ chanClosed chan
            case chc of
                Just (ct, r) -> CE.throwIO $ ChannelClosedException ct r
                Nothing -> CE.throwIO $ ConnectionClosedException Abnormal "unknown reason"

waitForAllConfirms :: Channel -> STM (IntSet.IntSet, IntSet.IntSet)
waitForAllConfirms chan = do
  pending <- readTVar $ (unconfirmedSet chan)
  check (IntSet.null pending)
  return =<< (,)
    <$> swapTVar (ackedSet chan) IntSet.empty
    <*> swapTVar (nackedSet chan) IntSet.empty
