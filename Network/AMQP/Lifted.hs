{-# LANGUAGE FlexibleContexts #-}

module Network.AMQP.Lifted
       ( consumeMsgs
       , consumeMsgs'
       )
       where

import qualified Network.AMQP as A
import Network.AMQP.Types
import Control.Monad.Trans.Control
import Data.Text (Text)
import Control.Monad

-- | @consumeMsgs chan queueName ack callback@ subscribes to the given queue and returns a consumerTag. For any incoming message, the callback will be run. If @ack == 'Ack'@ you will have to acknowledge all incoming messages (see 'ackMsg' and 'ackEnv')
--
-- NOTE: The callback will be run on the same thread as the channel thread (every channel spawns its own thread to listen for incoming data) so DO NOT perform any request on @chan@ inside the callback (however, you CAN perform requests on other open channels inside the callback, though I wouldn't recommend it).
-- Functions that can safely be called on @chan@ are 'ackMsg', 'ackEnv', 'rejectMsg', 'recoverMsgs'. If you want to perform anything more complex, it's a good idea to wrap it inside 'forkIO'.
--
-- In addition, while the callback function @(('Message', 'Envelope') -> m ())@
-- has access to the captured state, all its side-effects in m are discarded.
consumeMsgs :: MonadBaseControl IO m
            => A.Channel
            -> Text -- ^ Specifies the name of the queue to consume from.
            -> A.Ack
            -> ((A.Message, A.Envelope) -> m ())
            -> m A.ConsumerTag
consumeMsgs chan queueName ack callback =
    liftBaseWith $ \runInIO ->
        A.consumeMsgs chan queueName ack (void . runInIO . callback)

-- | an extended version of @consumeMsgs@ that allows you to include arbitrary arguments.
consumeMsgs' :: MonadBaseControl IO m
             => A.Channel
             -> Text -- ^ Specifies the name of the queue to consume from.
             -> A.Ack
             -> ((A.Message, A.Envelope) -> m ())
             -> FieldTable
             -> m A.ConsumerTag
consumeMsgs' chan queueName ack callback args =
    liftBaseWith $ \runInIO ->
        A.consumeMsgs' chan queueName ack (void . runInIO . callback) args
