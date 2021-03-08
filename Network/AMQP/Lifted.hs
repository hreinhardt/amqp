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

-- | Lifted version of 'Network.AMQP.consumeMsgs' (please look there for documentation).
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

-- | an extended version of @consumeMsgs@ that allows you to define a consumer cancellation callback and include arbitrary arguments.
consumeMsgs' :: MonadBaseControl IO m
             => A.Channel
             -> Text -- ^ Specifies the name of the queue to consume from.
             -> A.Ack
             -> ((A.Message, A.Envelope) -> m ())
             -> (ConsumerTag -> m ())
             -> FieldTable
             -> m A.ConsumerTag
consumeMsgs' chan queueName ack callback cancelled args =
    liftBaseWith $ \runInIO ->
        A.consumeMsgs' chan queueName ack (void . runInIO . callback) (void . runInIO . cancelled) args
