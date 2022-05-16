{-|
Module      : ConnectionManager
Description : Demo showing how AMQP connections and channels can be managed to deal with exceptions

This module should demonstrate how to
  - Handle an initial connection if the AMQP server is stopped or unreachable
  - Handle an AMQP server being stopped or unreachable while executing
  - Manage a pool of channels (using Data.Pool) so that you are not creating channels too often
     see https://www.rabbitmq.com/production-checklist.html#apps-connection-churn
  - Manage a single shared connection
     see https://www.rabbitmq.com/production-checklist.html#apps-connection-management
  - Automatically restart consumers (`consumeMsgs`) when the connection is restarted
     see `addOnReconnect` and its use in the Main.hs demo


Some notes on usage
  - Use Network.AMQP version 0.22.1 or above as it contains a fix for a potential connection issue
     https://github.com/hreinhardt/amqp/commit/ff169bbb8eec2d62efb4819f56f2c2d679ff4fc5
     In general always use the latest version possible
  - There are various settings in `Opts` that you can configure.
     E.g. Changing the pool size and how long to keep a channel open
  - Control.Exception.Safe is used to avoid catching exceptions that should not be handled by user code
     See https://hackage.haskell.org/package/safe-exceptions
  - Read the Hackage docs esp the section on "Exceptions in the callback".
  - Data.Pool does most of the heavy lifting for managing the channels


Please note that this is an example and should not be considered production ready as-is.
This code has not undergone the same testing as the core modules.
-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module ConnectionManager
    ( Handle
    , Opts(..)
    , addOnReconnect
    , closeHandle
    , defaultOpts
    , mkHandle
    , withChannel
    , withConnection
    ) where

import qualified Control.Concurrent.MVar as Mv
import           Control.Concurrent.STM (atomically)
import qualified Control.Concurrent.STM.TVar as Tv
import           Control.Concurrent (threadDelay)
import           Control.Exception.Safe (catch, throwM, SomeException)
import           Data.Foldable (sequenceA_)
import           Data.Maybe (fromMaybe)
import qualified Data.Pool as Pl
import qualified Network.AMQP as Rb
import Data.Time (NominalDiffTime)
import           Safe (atMay, lastMay)


-- | Connection options
data Opts = Opts
  { opKeepChannelOpenSeconds :: !NominalDiffTime     -- ^ Amount of time for which an unused resource is kept open. The smallest acceptable value is 0.5
  , opMaxPooledChannels :: !Int                      -- ^ Maximum number of channels to keep open. The smallest acceptable value is 1.
  , opRetyConnectionBackoffMilliseconds :: ![Int]    -- ^ milliseconds to delay between connection attempts
  , opRetyConnectionMaxAttempts :: !(Maybe Int)      -- ^ How many times to retry connection. Nothing = never
  , opChanCreateFn :: !(Maybe (Rb.Channel -> IO ())) -- ^ Function to run on each new connection, e.g. setting qos
  }


defaultOpts :: Opts
defaultOpts =
  Opts
    { opKeepChannelOpenSeconds = 60
    , opMaxPooledChannels = 5
    , opRetyConnectionBackoffMilliseconds = [100, 250, 475, 813, 1_319, 2_078, 3_217, 4_926]
    , opRetyConnectionMaxAttempts = Just 200
    , opChanCreateFn = Nothing
    }



-- Combined connection and pool
-- This makes it easier to ensure the pool is not used while the connection is being recreated etc
-- i.e. a pool is associated with a single open connection
newtype Mcp = Mcp (Mv.MVar (Rb.Connection, Pl.Pool Rb.Channel))


-- | Opaque handle representing a AMQP connection
-- This is the type that the user will use rather than the normal Network.AMQP.Connection
data Handle = Handle
  { hMcp :: !Mcp -- ^ Connection and it's pool of channels
  , hWithConnection :: !(forall a. Handle -> (Rb.Connection -> IO a) -> IO a) -- ^ Helper method for the public withConnection function
  , hOnReconnect :: !(Tv.TVar [IO ()]) -- ^ Actions to perform when reconnecting to rabbit
  }


-- | Create a new handle to manage a rabbit connection
mkHandle
  :: Rb.ConnectionOpts -- ^ Connection options
  -> Opts -- ^ Connection management options
  -> IO Handle
mkHandle ropts copts = do
  mcp <- Mv.newEmptyMVar
  rs <- Tv.newTVarIO []

  initMcp Handle
            { hMcp = Mcp mcp
            , hWithConnection = withConnection'
            , hOnReconnect = rs
            }


  where
    -- | Create a connection and it's associated pool of channels
    initMcp :: Handle -> IO Handle
    initMcp h = do
      let (Mcp mcp) = hMcp h
      -- Create a new channel pool for the new connection
      pool <- Pl.createPool (createChan h) Rb.closeChannel 1 (opKeepChannelOpenSeconds copts) (opMaxPooledChannels copts)
      -- Create a new connection
      conn <- newRabbitConnection h
      Mv.putMVar mcp (conn, pool)
      pure h


    createChan :: Handle -> IO Rb.Channel
    createChan h = do
      let (Mcp mcp) = hMcp h
      (c, _) <- Mv.readMVar mcp
      -- Create a new channel
      -- Optionally call opChanCreateFn if it is not Nothing
      -- Call addChannelExceptionHandler so we can manage any channel exceptions
      manageRabbitException
        h
        (do
          ch <- Rb.openChannel c

          case opChanCreateFn copts of
            Nothing -> pure ()
            Just f -> f ch

          Rb.addChannelExceptionHandler ch (onRabbitException h)
          pure ch
        )


    onRabbitException :: Handle -> SomeException -> IO a
    onRabbitException h ex =
      -- Use `isNormalChannelClose` to see if the channel was closed normally or if there was an error
      -- See the docs for `isNormalChannelClose` for details
      if Rb.isNormalChannelClose ex
        then
          -- Normal close, so rethrow so that the normal shutdown can occur
          throwM ex
        else do
          -- Unexpected exception. Assume that the connection will is terminated and start a new one.
          restartConnection h
          throwM ex

    restartConnection :: Handle -> IO ()
    restartConnection h = do
      let (Mcp mcp) = hMcp h
      (_conn, pool) <- Mv.takeMVar mcp

      -- Try to close any open channels from the old pool
      Pl.destroyAllResources pool
      -- New connection and pool
      _ <- initMcp h

      -- Run all the actions that the user wanted to happen after a reconnect
      rs <- Tv.readTVarIO $ hOnReconnect h
      sequenceA_ rs


    manageRabbitException :: Handle -> IO a -> IO a
    manageRabbitException h fn =
      catch fn (onRabbitException h)


    withConnection' :: Handle -> (Rb.Connection -> IO a) -> IO a
    withConnection' h@(Handle (Mcp cp') _ _) fn = do
      (conn, _pool) <- Mv.readMVar cp'
      -- Run the user function with a connection
      -- Any exception in the user function is assumed to be problem with the connection
      -- The user should only run functions that actually need the connection in the callback
      manageRabbitException h (fn conn)


    newRabbitConnection :: Handle -> IO Rb.Connection
    newRabbitConnection h = do
      -- Get a new connection, possibly waiting for the server
      conn <- tryNewRabbitConnection (fromMaybe 0 $ opRetyConnectionMaxAttempts copts) 0
      -- Add a handler to watch for connection closes
      Rb.addConnectionClosedHandler conn True (restartConnection h)
      pure conn


    tryNewRabbitConnection :: Int -> Int -> IO Rb.Connection
    tryNewRabbitConnection retriesLeft atRetry = do
      -- Loop until connected
      catch
        (Rb.openConnection'' ropts)
        (\(ex::SomeException) ->
          if retriesLeft <= 0
            then throwM ex
          else do
            let
              -- Get the back off values
              backoff = opRetyConnectionBackoffMilliseconds copts
              -- Largest possible back off, default of 200ms if none was set
              largestBackoffMs = fromMaybe 200 . lastMay $ backoff
              -- Delay for current number of retries
              delay = 1_000 * fromMaybe largestBackoffMs (atMay backoff atRetry)

            -- Delay
            threadDelay delay
            -- Try again
            tryNewRabbitConnection (retriesLeft - 1) (atRetry + 1)
         )


-- | Close the handle's connection and channels
closeHandle :: Handle -> IO ()
closeHandle (Handle (Mcp mcp) _ _) =
  Mv.tryTakeMVar mcp >>= \case
    Nothing -> pure ()
    Just (conn, _) -> Rb.closeConnection conn


-- | Perform an operation with a pooled channel. Keep this callback as small as possible, only functions that actually need a channel
withChannel :: Handle -> (Rb.Channel -> IO a) -> IO a
withChannel (Handle (Mcp mcp) _ _) fn = do
  (_, pool) <- Mv.readMVar mcp
  Pl.withResource pool fn


-- | Perform an operation with the connection. Keep this callback as small as possible, only functions that actually need the connection
withConnection :: Handle -> (Rb.Connection -> IO a) -> IO a
withConnection h@(Handle _ w _) = w h


-- | Add a callback to run when the connection is reconnected
-- Note this does not run the callback immediately only on reconnect
addOnReconnect :: Handle -> IO () -> IO ()
addOnReconnect (Handle _ _ rs') fn =
  atomically . Tv.modifyTVar' rs' $ \rs -> fn : rs
