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
    , retryUntilConnectionClose
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


data Opts = Opts
  { opKeepChannelOpenSeconds :: !NominalDiffTime
  , opMaxPooledChannels :: !Int
  , opRetyConnectionBackoffMilliseconds :: ![Int]
  , opRetyConnectionMaxAttempts :: !(Maybe Int)
  , opChanCreateFn :: !(Maybe (Rb.Channel -> IO ()))
  }


defaultOpts :: Opts
defaultOpts =
  Opts
    { opKeepChannelOpenSeconds = 60 -- ^ Amount of time for which an unused resource is kept open. The smallest acceptable value is 0.5
    , opMaxPooledChannels = 5 -- ^ Maximum number of channels to keep open. The smallest acceptable value is 1.
    , opRetyConnectionBackoffMilliseconds = [100, 250, 475, 813, 1_319, 2_078, 3_217, 4_926] -- ^ milliseconds to delay between connection attempts
    , opRetyConnectionMaxAttempts = Just 200 -- ^ How many times to retry connection. Nothing = never
    , opChanCreateFn = Nothing -- ^ Function to run on each new connection, e.g. setting qos
    }



-- Combined connection and pool, makes it easier to ensure the pool is not used while the connection is being recreated etc
newtype Mcp = Mcp (Mv.MVar (Rb.Connection, Pl.Pool Rb.Channel))

-- | Opaque handle representing a rabbit connection
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
      pool <- Pl.createPool (createChan h) Rb.closeChannel 1 (opKeepChannelOpenSeconds copts) (opMaxPooledChannels copts)
      conn <- newRabbitConnection h
      Mv.putMVar mcp (conn, pool)
      pure h


    createChan :: Handle -> IO Rb.Channel
    createChan h = do
      let (Mcp mcp) = hMcp h
      (c, _) <- Mv.readMVar mcp
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
      if Rb.isNormalChannelClose ex
        then
          throwM ex
        else do
          restartConnection h
          throwM ex

    restartConnection :: Handle -> IO ()
    restartConnection h = do
      let (Mcp mcp) = hMcp h
      (_conn, pool) <- Mv.takeMVar mcp
      Pl.destroyAllResources pool
      _ <- initMcp h
      rs <- Tv.readTVarIO $ hOnReconnect h
      sequenceA_ rs


    manageRabbitException :: Handle -> IO a -> IO a
    manageRabbitException h fn =
      catch fn (onRabbitException h)


    withConnection' :: Handle -> (Rb.Connection -> IO a) -> IO a
    withConnection' h@(Handle (Mcp cp') _ _) fn = do
      (conn, _pool) <- Mv.readMVar cp'
      manageRabbitException h (fn conn)


    newRabbitConnection :: Handle -> IO Rb.Connection
    newRabbitConnection h = do
      conn <- tryNewRabbitConnection (fromMaybe 0 $ opRetyConnectionMaxAttempts copts) 0
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
              backoff = opRetyConnectionBackoffMilliseconds copts
              -- Largest possible back off, default of 200ms if none was set
              largestBackoffMs = fromMaybe 200 . lastMay $ backoff
              -- Delay for current number of retries
              delay = 1_000 * fromMaybe largestBackoffMs (atMay backoff atRetry)

            threadDelay delay
            tryNewRabbitConnection (retriesLeft - 1) (atRetry + 1)
         )

closeHandle :: Handle -> IO ()
closeHandle (Handle (Mcp mcp) _ _) =
  Mv.tryTakeMVar mcp >>= \case
    Nothing -> pure ()
    Just (conn, _) -> Rb.closeConnection conn


withChannel :: Handle -> (Rb.Channel -> IO a) -> IO a
withChannel (Handle (Mcp mcp) _ _) fn = do
  (_, pool) <- Mv.readMVar mcp
  Pl.withResource pool fn


withConnection :: Handle -> (Rb.Connection -> IO a) -> IO a
withConnection h@(Handle _ w _) = w h


retryUntilConnectionClose :: Int -> IO a -> IO a
retryUntilConnectionClose retrySecs fn =
  catch fn handleEx

  where
    handleEx (_::SomeException) = do
      threadDelay retrySecs
      retryUntilConnectionClose retrySecs fn


addOnReconnect :: Handle -> IO () -> IO ()
addOnReconnect (Handle _ _ rs') fn =
  atomically . Tv.modifyTVar' rs' $ \rs -> fn : rs
