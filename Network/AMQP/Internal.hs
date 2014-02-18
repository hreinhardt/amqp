{-# LANGUAGE BangPatterns, DeriveDataTypeable, OverloadedStrings, ScopedTypeVariables #-}
module Network.AMQP.Internal where

import Control.Concurrent
import Control.Monad
import Data.Binary
import Data.Binary.Get
import Data.Binary.Put as BPut
import Data.Int (Int64)
import Data.Maybe
import Data.Text (Text)
import Data.Typeable
import Network

import qualified Control.Exception as CE
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map as M
import qualified Data.Foldable as F
import qualified Data.IntMap as IM
import qualified Data.Sequence as Seq
import qualified Data.Text as T
import qualified Data.Text.Encoding as E
import qualified Network.Connection as Conn

import Network.AMQP.Protocol
import Network.AMQP.Types
import Network.AMQP.Helpers
import Network.AMQP.Generated


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
                msgContentType :: Maybe Text,
                msgReplyTo :: Maybe Text,
                msgCorrelationID :: Maybe Text,
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
                    connChannels :: (MVar (IM.IntMap (Channel, ThreadId))), --open channels (channelID => (Channel, ChannelThread))
                    connMaxFrameSize :: Int, --negotiated maximum frame size
                    connClosed :: MVar (Maybe String),
                    connClosedLock :: MVar (), -- used by closeConnection to block until connection-close handshake is complete
                    connWriteLock :: MVar (), -- to ensure atomic writes to the socket
                    connClosedHandlers :: MVar [IO ()],
                    lastChannelID :: MVar Int, -- for auto-incrementing the channelIDs
                    connLastReceived :: MVar Int64, -- the timestamp from a monotonic clock when the last frame was received
                    connLastSent :: MVar Int64 -- the timestamp from a monotonic clock when the last frame was written
                }

-- | Represents the parameters to connect to a broker or a cluster of brokers.
-- See 'defaultConnectionOpts'.
--
-- /NOTICE/: The field 'coMaxChannel' was only added for future use, as the respective functionality is not yet implemented.
data ConnectionOpts = ConnectionOpts {
                            coServers :: ![(String, PortNumber)], -- ^ A list of host-port pairs. Useful in a clustered setup to connect to the first available host.
                            coVHost :: !Text, -- ^ The VHost to connect to.
                            coAuth :: ![SASLMechanism], -- ^ The 'SASLMechanism's to use for authenticating with the broker.
                            coMaxFrameSize :: !(Maybe Word32), -- ^ The maximum frame size to be used. If not specified, no limit is assumed.
                            coHeartbeatDelay :: !(Maybe Word16), -- ^ The delay in seconds, after which the client expects a heartbeat frame from the broker. If 'Nothing', the value suggested by the broker is used. Use @Just 0@ to disable the heartbeat mechnism.
                            coMaxChannel :: !(Maybe Word16), -- ^ The maximum number of channels the client will use.
                            coTLSSettings :: Maybe TLSSettings -- ^ Whether or not to connect to servers using TLS. See http://www.rabbitmq.com/ssl.html for details.
                        }
-- | Represents the kind of TLS connection to establish.
data TLSSettings =
    TLSTrusted   -- ^ Require trusted certificates (Recommended).
  | TLSUntrusted -- ^ Allow untrusted certificates (Discouraged. Vulnerable to man-in-the-middle attacks)

connectionTLSSettings :: TLSSettings -> Maybe Conn.TLSSettings
connectionTLSSettings tlsSettings =
  Just $ case tlsSettings of
    TLSTrusted -> Conn.TLSSettingsSimple False False False
    TLSUntrusted -> Conn.TLSSettingsSimple True False False

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
        (\(e :: CE.IOException) -> myThreadId >>= killConnection conn (show e))
    connectionReceiver conn
  where
    forwardToChannel 0 (MethodPayload Connection_close_ok) =  myThreadId >>= killConnection conn "closed by user"
    forwardToChannel 0 (MethodPayload (Connection_close _ (ShortString errorMsg) _ _)) = do
        writeFrame (connHandle conn) $ Frame 0 $ MethodPayload Connection_close_ok
        myThreadId >>= killConnection conn (T.unpack errorMsg)
    forwardToChannel 0 HeartbeatPayload = return ()
    forwardToChannel 0 payload = putStrLn $ "Got unexpected msg on channel zero: " ++ show payload
    forwardToChannel chanID payload = do
        --got asynchronous msg => forward to registered channel
        withMVar (connChannels conn) $ \cs -> do
            case IM.lookup (fromIntegral chanID) cs of
                Just c -> writeChan (inQueue $ fst c) payload
                Nothing -> putStrLn $ "ERROR: channel not open " ++ show chanID

-- | Opens a connection to a broker specified by the given 'ConnectionOpts' parameter.
openConnection'' :: ConnectionOpts -> IO Connection
openConnection'' connOpts = withSocketsDo $ do
    handle <- connect $ coServers connOpts
    (maxFrameSize, heartbeatTimeout) <- CE.handle (\(_ :: CE.IOException) -> CE.throwIO $ ConnectionClosedException "Handshake failed. Please check the RabbitMQ logs for more information") $ do
        Conn.connectionPut handle $ BS.append (BC.pack "AMQP")
                (BS.pack [
                          1
                        , 1 --TCP/IP
                        , 0 --Major Version
                        , 9 --Minor Version
                       ])

        -- S: connection.start
        Frame 0 (MethodPayload (Connection_start _ _ _ (LongString serverMechanisms) _)) <- readFrame handle
        selectedSASL <- selectSASLMechanism handle serverMechanisms

        -- C: start_ok
        writeFrame handle $ start_ok selectedSASL
        -- S: secure or tune
        Frame 0 (MethodPayload (Connection_tune _ frame_max sendHeartbeat)) <- handleSecureUntilTune handle selectedSASL
        -- C: tune_ok
        let maxFrameSize = chooseMin frame_max $ coMaxFrameSize connOpts
            finalHeartbeatSec = fromMaybe sendHeartbeat (coHeartbeatDelay connOpts)
            heartbeatTimeout = mfilter (/=0) (Just finalHeartbeatSec)

        writeFrame handle (Frame 0 (MethodPayload
            --TODO: handle channel_max
            (Connection_tune_ok 0 maxFrameSize finalHeartbeatSec)
            ))
        -- C: open
        writeFrame handle open

        -- S: open_ok
        Frame 0 (MethodPayload (Connection_open_ok _)) <- readFrame handle

        -- Connection established!
        return (maxFrameSize, heartbeatTimeout)

    --build Connection object
    cChannels <- newMVar IM.empty
    lastChanID <- newMVar 0
    cClosed <- newMVar Nothing
    writeLock <- newMVar ()
    ccl <- newEmptyMVar
    cClosedHandlers <- newMVar []
    cLastReceived <- getTimestamp >>= newMVar
    cLastSent <- getTimestamp >>= newMVar
    let conn = Connection handle cChannels (fromIntegral maxFrameSize) cClosed ccl writeLock cClosedHandlers lastChanID cLastReceived cLastSent

    --spawn the connectionReceiver
    connThread <- forkIO $ CE.finally (connectionReceiver conn) $ do
                -- try closing socket
                CE.catch (Conn.connectionClose handle) (\(_ :: CE.SomeException) -> return ())

                -- mark as closed
                modifyMVar_ cClosed $ return . Just . maybe "unknown reason" id

                --kill all channel-threads
                modifyMVar_ cChannels $ \x -> do
                    mapM_ (killThread . snd) $ IM.elems x
                    return IM.empty

                -- mark connection as closed, so all pending calls to 'closeConnection' can now return
                void $ tryPutMVar ccl ()

                -- notify connection-close-handlers
                withMVar cClosedHandlers sequence

    case heartbeatTimeout of
        Nothing      -> return ()
        Just timeout ->  do
            heartbeatThread <- watchHeartbeats conn (fromIntegral timeout) connThread
            addConnectionClosedHandler conn True (killThread heartbeatThread)

    return conn
  where
    connect ((host, port) : rest) = do
        ctx <- Conn.initConnectionContext
        result <- CE.try (Conn.connectTo ctx $ Conn.ConnectionParams
                              { Conn.connectionHostname  = host
                              , Conn.connectionPort      = port
                              , Conn.connectionUseSecure = tlsSettings
                              , Conn.connectionUseSocks  = Nothing
                              })
        either
            (\(ex :: CE.SomeException) -> do
                putStrLn $ "Error connecting to "++show (host, port)++": "++show ex
                connect rest)
            (return)
            result
    connect [] = CE.throwIO $ ConnectionClosedException $ "Could not connect to any of the provided brokers: " ++ show (coServers connOpts)
    tlsSettings = maybe Nothing connectionTLSSettings (coTLSSettings connOpts)
    selectSASLMechanism handle serverMechanisms =
        let serverSaslList = T.split (== ' ') $ E.decodeUtf8 serverMechanisms
            clientMechanisms = coAuth connOpts
            clientSaslList = map saslName clientMechanisms
            maybeSasl = F.find (\(SASLMechanism name _ _) -> elem name serverSaslList) clientMechanisms
        in abortIfNothing maybeSasl handle
            ("None of the provided SASL mechanisms "++show clientSaslList++" is supported by the server "++show serverSaslList++".")

    start_ok sasl = (Frame 0 (MethodPayload (Connection_start_ok (FieldTable M.empty)
        (ShortString $ saslName sasl)
        (LongString $ saslInitialResponse sasl)
        (ShortString "en_US")) ))

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
        CE.throwIO $ ConnectionClosedException msg

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

    checkReceiveTimeout = check (connLastReceived conn) receiveTimeout
        (killConnection conn "killed connection after missing 2 consecutive heartbeats" connThread)

    checkSendTimeout = check (connLastSent conn) sendTimeout
        (writeFrame (connHandle conn) (Frame 0 HeartbeatPayload))

    check var timeout_µs action = withMVar var $ \lastFrameTime -> do
        time <- getTimestamp
        when (time >= lastFrameTime + timeout_µs) $ do
            action

updateLastSent :: Connection -> IO ()
updateLastSent conn = modifyMVar_ (connLastSent conn) (const getTimestamp)

updateLastReceived :: Connection -> IO ()
updateLastReceived conn = modifyMVar_ (connLastReceived conn) (const getTimestamp)

-- | kill the connection thread abruptly
killConnection :: Connection -> String -> ThreadId -> IO ()
killConnection conn msg connThread = do
    modifyMVar_ (connClosed conn) $ const $ return $ Just msg
    killThread connThread

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

-- | @addConnectionClosedHandler conn ifClosed handler@ adds a @handler@ that will be called after the connection is closed (either by calling @closeConnection@ or by an exception). If the @ifClosed@ parameter is True and the connection is already closed, the handler will be called immediately. If @ifClosed == False@ and the connection is already closed, the handler will never be called
addConnectionClosedHandler :: Connection -> Bool -> IO () -> IO ()
addConnectionClosedHandler conn ifClosed handler = do
    withMVar (connClosed conn) $ \cc ->
        case cc of
            -- connection is already closed, so call the handler directly
            Just _ | ifClosed == True -> handler

            -- otherwise add it to the list
            _ -> modifyMVar_ (connClosedHandlers conn) $ \old -> return $ handler:old

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
    let ret = runGetOrFail get (BL.append dat dat')
    case ret of
        Left (_, _, errMsg) -> error $ "readFrame fail: " ++ errMsg
        Right (_, consumedBytes, _) | consumedBytes /= fromIntegral (len+8) ->
            error $ "readFrame: parser should read " ++ show (len+8) ++ " bytes; but read " ++ show consumedBytes
        Right (_, _, frame) -> return frame

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

                    chanActive :: Lock, -- used for flow-control. if lock is closed, no content methods will be sent
                    chanClosed :: MVar (Maybe String),
                    consumers :: MVar (M.Map Text ((Message, Envelope) -> IO ())), -- who is consumer of a queue? (consumerTag => callback)
                    returnListeners :: MVar ([(Message, PublishError) -> IO ()])
                }

msgFromContentHeaderProperties :: ContentHeaderProperties -> BL.ByteString -> Message
msgFromContentHeaderProperties (CHBasic content_type _ headers delivery_mode _ correlation_id reply_to _ message_id timestamp _ _ _ _) body =
    let msgId = fromShortString message_id
        contentType = fromShortString content_type
        replyTo = fromShortString reply_to
        correlationID = fromShortString correlation_id
    in Message body (fmap intToDeliveryMode delivery_mode) timestamp msgId contentType replyTo correlationID headers
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
    isResponse _ = True

    --Basic.Deliver: forward msg to registered consumer
    handleAsync (ContentMethod (Basic_deliver (ShortString consumerTag) deliveryTag redelivered (ShortString exchange)
                                                (ShortString routingKey))
                                properties body) =
        withMVar (consumers chan) (\s -> do
            case M.lookup consumerTag s of
                Just subscriber -> do
                    let msg = msgFromContentHeaderProperties properties body
                    let env = Envelope {envDeliveryTag = deliveryTag, envRedelivered = redelivered,
                                    envExchangeName = exchange, envRoutingKey = routingKey, envChannel = chan}

                    CE.catch (subscriber (msg, env))
                        (\(e::CE.SomeException) -> putStrLn $ "AMQP callback threw exception: " ++ show e)
                Nothing ->
                    -- got a message, but have no registered subscriber; so drop it
                    return ()
            )
    handleAsync (SimpleMethod (Channel_close _ (ShortString errorMsg) _ _)) = do
        closeChannel' chan errorMsg
        killThread =<< myThreadId
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
                putStrLn $ "return listener on channel ["++(show $ channelID chan)++"] handling error ["++show pubError++"] threw exception: "++show ex
    handleAsync m = error ("Unknown method: " ++ show m)

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

-- closes the channel internally; but doesn't tell the server
closeChannel' :: Channel -> Text -> IO ()
closeChannel' c reason = do
    modifyMVar_ (connChannels $ connection c) $ \old -> return $ IM.delete (fromIntegral $ channelID c) old
    -- mark channel as closed
    modifyMVar_ (chanClosed c) $ \x -> do
        if isNothing x
            then do
                void $ killLock $ chanActive c
                killOutstandingResponses $ outstandingResponses c
                return $ Just $ maybe (T.unpack reason) id x
            else return x
  where
    killOutstandingResponses :: MVar (Seq.Seq (MVar a)) -> IO ()
    killOutstandingResponses outResps = do
        modifyMVar_ outResps $ \val -> do
            F.mapM_ (\x -> tryPutMVar x $ error "channel closed") val
            return undefined

-- | opens a new channel on the connection
--
-- There's currently no closeChannel method, but you can always just close the connection (the maximum number of channels is 65535).
openChannel :: Connection -> IO Channel
openChannel c = do
    newInQueue <- newChan
    outRes <- newMVar Seq.empty
    lastConsTag <- newMVar 0
    ca <- newLock

    closed <- newMVar Nothing
    conss <- newMVar M.empty
    listeners <- newMVar []

    --get a new unused channelID
    newChannelID <- modifyMVar (lastChannelID c) $ \x -> return (x+1, x+1)

    let newChannel = Channel c newInQueue outRes (fromIntegral newChannelID) lastConsTag ca closed conss listeners

    thrID <- forkIO $ CE.finally (channelReceiver newChannel)
        (closeChannel' newChannel "closed")

    --add new channel to connection's channel map
    modifyMVar_ (connChannels c) (return . IM.insert newChannelID (newChannel, thrID))

    (SimpleMethod (Channel_open_ok _)) <- request newChannel (SimpleMethod (Channel_open (ShortString "")))
    return newChannel

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
        Just r -> CE.throwIO $ ConnectionClosedException r
        Nothing -> do
            chc <- readMVar $ chanClosed chan
            case chc of
                Just r -> CE.throwIO $ ChannelClosedException r
                Nothing -> CE.throwIO $ ConnectionClosedException "unknown reason"

----------------------------- EXCEPTIONS ---------------------------

data AMQPException =
    -- | the 'String' contains the reason why the channel was closed
    ChannelClosedException String
    | ConnectionClosedException String -- ^ String may contain a reason
  deriving (Typeable, Show, Ord, Eq)
instance CE.Exception AMQPException
