module Network.AMQP.Generated where

import Data.Binary
import Data.Binary.Get
import Data.Binary.Put
import Data.Bits
import Data.Maybe
import Network.AMQP.Types

getContentHeaderProperties :: ShortInt -> Get ContentHeaderProperties
getContentHeaderProperties 10 = getPropBits 0 >>= \[] ->  return CHConnection
getContentHeaderProperties 20 = getPropBits 0 >>= \[] ->  return CHChannel
getContentHeaderProperties 40 = getPropBits 0 >>= \[] ->  return CHExchange
getContentHeaderProperties 50 = getPropBits 0 >>= \[] ->  return CHQueue
getContentHeaderProperties 60 = getPropBits 14 >>= \[a,b,c,d,e,f,g,h,i,j,k,l,m,n] -> condGet a >>= \a' -> condGet b >>= \b' -> condGet c >>= \c' -> condGet d >>= \d' -> condGet e >>= \e' -> condGet f >>= \f' -> condGet g >>= \g' -> condGet h >>= \h' -> condGet i >>= \i' -> condGet j >>= \j' -> condGet k >>= \k' -> condGet l >>= \l' -> condGet m >>= \m' -> condGet n >>= \n' ->  return (CHBasic a' b' c' d' e' f' g' h' i' j' k' l' m' n' )
getContentHeaderProperties 90 = getPropBits 0 >>= \[] ->  return CHTx
getContentHeaderProperties 85 = getPropBits 0 >>= \[] ->  return CHConfirm

getContentHeaderProperties n = error ("Unexpected content header properties: " ++ show n)
putContentHeaderProperties :: ContentHeaderProperties -> Put
putContentHeaderProperties CHConnection = putPropBits []
putContentHeaderProperties CHChannel = putPropBits []
putContentHeaderProperties CHExchange = putPropBits []
putContentHeaderProperties CHQueue = putPropBits []
putContentHeaderProperties (CHBasic a b c d e f g h i j k l m n) = putPropBits [isJust a,isJust b,isJust c,isJust d,isJust e,isJust f,isJust g,isJust h,isJust i,isJust j,isJust k,isJust l,isJust m,isJust n]  >> condPut a >> condPut b >> condPut c >> condPut d >> condPut e >> condPut f >> condPut g >> condPut h >> condPut i >> condPut j >> condPut k >> condPut l >> condPut m >> condPut n
putContentHeaderProperties CHTx = putPropBits []
putContentHeaderProperties CHConfirm = putPropBits []

getClassIDOf :: ContentHeaderProperties -> ShortInt
getClassIDOf (CHConnection) = 10
getClassIDOf (CHChannel) = 20
getClassIDOf (CHExchange) = 40
getClassIDOf (CHQueue) = 50
getClassIDOf (CHBasic _ _ _ _ _ _ _ _ _ _ _ _ _ _) = 60
getClassIDOf (CHTx) = 90
getClassIDOf (CHConfirm) = 85

data ContentHeaderProperties =
	CHConnection

	|CHChannel

	|CHExchange

	|CHQueue

	|CHBasic
		(Maybe ShortString) -- content-type
		(Maybe ShortString) -- content-encoding
		(Maybe FieldTable) -- headers
		(Maybe Octet) -- delivery-mode
		(Maybe Octet) -- priority
		(Maybe ShortString) -- correlation-id
		(Maybe ShortString) -- reply-to
		(Maybe ShortString) -- expiration
		(Maybe ShortString) -- message-id
		(Maybe Timestamp) -- timestamp
		(Maybe ShortString) -- typ
		(Maybe ShortString) -- user-id
		(Maybe ShortString) -- app-id
		(Maybe ShortString) -- reserved
	|CHTx

	|CHConfirm


	deriving Show

--Bits need special handling because AMQP requires contiguous bits to be packed into a Word8
-- | Packs up to 8 bits into a Word8
putBits :: [Bit] -> Put
putBits = putWord8 . putBits' 0
putBits' :: Int -> [Bit] -> Word8
putBits' _ [] = 0
putBits' offset (x:xs) = (shiftL (toInt x) offset) .|. (putBits' (offset+1) xs)
    where toInt True = 1
          toInt False = 0
getBits :: Int -> Get [Bit]
getBits num = getWord8 >>= return . getBits' num 0
getBits' :: Int -> Int -> Word8 -> [Bit]
getBits' 0 _ _ = []
getBits' num offset x = ((x .&. (2^offset)) /= 0) : (getBits' (num-1) (offset+1) x)
-- | Packs up to 15 Bits into a Word16 (=Property Flags)
putPropBits :: [Bit] -> Put
putPropBits = putWord16be . putPropBits' 0
putPropBits' :: Int -> [Bit] -> Word16
putPropBits' _ [] = 0
putPropBits' offset (x:xs) = (shiftL (toInt x) (15-offset)) .|. (putPropBits' (offset+1) xs)
    where toInt True = 1
          toInt False = 0
getPropBits :: Int -> Get [Bit]
getPropBits num = getWord16be >>= return . getPropBits' num 0
getPropBits' :: Int -> Int -> Word16 -> [Bit]
getPropBits' 0 _ _ = []
getPropBits' num offset x = ((x .&. (2^(15-offset))) /= 0) : (getPropBits' (num-1) (offset+1) x)
condGet :: Binary a => Bool -> Get (Maybe a)
condGet False = return Nothing
condGet True = get >>= return . Just

condPut :: Binary a => Maybe a -> Put
condPut = maybe (return ()) put
instance Binary MethodPayload where
	put (Connection_start a b c d e) = putWord16be 10 >> putWord16be 10 >> put a >> put b >> put c >> put d >> put e
	put (Connection_start_ok a b c d) = putWord16be 10 >> putWord16be 11 >> put a >> put b >> put c >> put d
	put (Connection_secure a) = putWord16be 10 >> putWord16be 20 >> put a
	put (Connection_secure_ok a) = putWord16be 10 >> putWord16be 21 >> put a
	put (Connection_tune a b c) = putWord16be 10 >> putWord16be 30 >> put a >> put b >> put c
	put (Connection_tune_ok a b c) = putWord16be 10 >> putWord16be 31 >> put a >> put b >> put c
	put (Connection_open a b c) = putWord16be 10 >> putWord16be 40 >> put a >> put b >> put c
	put (Connection_open_ok a) = putWord16be 10 >> putWord16be 41 >> put a
	put (Connection_close a b c d) = putWord16be 10 >> putWord16be 50 >> put a >> put b >> put c >> put d
	put Connection_close_ok = putWord16be 10 >> putWord16be 51
	put (Channel_open a) = putWord16be 20 >> putWord16be 10 >> put a
	put (Channel_open_ok a) = putWord16be 20 >> putWord16be 11 >> put a
	put (Channel_flow a) = putWord16be 20 >> putWord16be 20 >> put a
	put (Channel_flow_ok a) = putWord16be 20 >> putWord16be 21 >> put a
	put (Channel_close a b c d) = putWord16be 20 >> putWord16be 40 >> put a >> put b >> put c >> put d
	put Channel_close_ok = putWord16be 20 >> putWord16be 41
	put (Exchange_declare a b c d e f g h i) = putWord16be 40 >> putWord16be 10 >> put a >> put b >> put c >> putBits [d,e,f,g,h] >> put i
	put Exchange_declare_ok = putWord16be 40 >> putWord16be 11
	put (Exchange_delete a b c d) = putWord16be 40 >> putWord16be 20 >> put a >> put b >> putBits [c,d]
	put Exchange_delete_ok = putWord16be 40 >> putWord16be 21
	put (Exchange_bind a b c d e f) = putWord16be 40 >> putWord16be 30 >> put a >> put b >> put c >> put d >> put e >> put f
	put Exchange_bind_ok = putWord16be 40 >> putWord16be 31
	put (Exchange_unbind a b c d e f) = putWord16be 40 >> putWord16be 40 >> put a >> put b >> put c >> put d >> put e >> put f
	put Exchange_unbind_ok = putWord16be 40 >> putWord16be 51
	put (Queue_declare a b c d e f g h) = putWord16be 50 >> putWord16be 10 >> put a >> put b >> putBits [c,d,e,f,g] >> put h
	put (Queue_declare_ok a b c) = putWord16be 50 >> putWord16be 11 >> put a >> put b >> put c
	put (Queue_bind a b c d e f) = putWord16be 50 >> putWord16be 20 >> put a >> put b >> put c >> put d >> put e >> put f
	put Queue_bind_ok = putWord16be 50 >> putWord16be 21
	put (Queue_unbind a b c d e) = putWord16be 50 >> putWord16be 50 >> put a >> put b >> put c >> put d >> put e
	put Queue_unbind_ok = putWord16be 50 >> putWord16be 51
	put (Queue_purge a b c) = putWord16be 50 >> putWord16be 30 >> put a >> put b >> put c
	put (Queue_purge_ok a) = putWord16be 50 >> putWord16be 31 >> put a
	put (Queue_delete a b c d e) = putWord16be 50 >> putWord16be 40 >> put a >> put b >> putBits [c,d,e]
	put (Queue_delete_ok a) = putWord16be 50 >> putWord16be 41 >> put a
	put (Basic_qos a b c) = putWord16be 60 >> putWord16be 10 >> put a >> put b >> put c
	put Basic_qos_ok = putWord16be 60 >> putWord16be 11
	put (Basic_consume a b c d e f g h) = putWord16be 60 >> putWord16be 20 >> put a >> put b >> put c >> putBits [d,e,f,g] >> put h
	put (Basic_consume_ok a) = putWord16be 60 >> putWord16be 21 >> put a
	put (Basic_cancel a b) = putWord16be 60 >> putWord16be 30 >> put a >> put b
	put (Basic_cancel_ok a) = putWord16be 60 >> putWord16be 31 >> put a
	put (Basic_publish a b c d e) = putWord16be 60 >> putWord16be 40 >> put a >> put b >> put c >> putBits [d,e]
	put (Basic_return a b c d) = putWord16be 60 >> putWord16be 50 >> put a >> put b >> put c >> put d
	put (Basic_deliver a b c d e) = putWord16be 60 >> putWord16be 60 >> put a >> put b >> put c >> put d >> put e
	put (Basic_get a b c) = putWord16be 60 >> putWord16be 70 >> put a >> put b >> put c
	put (Basic_get_ok a b c d e) = putWord16be 60 >> putWord16be 71 >> put a >> put b >> put c >> put d >> put e
	put (Basic_get_empty a) = putWord16be 60 >> putWord16be 72 >> put a
	put (Basic_ack a b) = putWord16be 60 >> putWord16be 80 >> put a >> put b
	put (Basic_reject a b) = putWord16be 60 >> putWord16be 90 >> put a >> put b
	put (Basic_recover_async a) = putWord16be 60 >> putWord16be 100 >> put a
	put (Basic_recover a) = putWord16be 60 >> putWord16be 110 >> put a
	put Basic_recover_ok = putWord16be 60 >> putWord16be 111
	put (Basic_nack a b c) = putWord16be 60 >> putWord16be 120 >> put a >> putBits [b,c]
	put Tx_select = putWord16be 90 >> putWord16be 10
	put Tx_select_ok = putWord16be 90 >> putWord16be 11
	put Tx_commit = putWord16be 90 >> putWord16be 20
	put Tx_commit_ok = putWord16be 90 >> putWord16be 21
	put Tx_rollback = putWord16be 90 >> putWord16be 30
	put Tx_rollback_ok = putWord16be 90 >> putWord16be 31
	put (Confirm_select a) = putWord16be 85 >> putWord16be 10 >> put a
	put Confirm_select_ok = putWord16be 85 >> putWord16be 11
	get = do
		classID <- getWord16be
		methodID <- getWord16be
		case (classID, methodID) of
			(10,10) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e ->  return (Connection_start a b c d e)
			(10,11) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Connection_start_ok a b c d)
			(10,20) -> get >>= \a ->  return (Connection_secure a)
			(10,21) -> get >>= \a ->  return (Connection_secure_ok a)
			(10,30) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Connection_tune a b c)
			(10,31) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Connection_tune_ok a b c)
			(10,40) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Connection_open a b c)
			(10,41) -> get >>= \a ->  return (Connection_open_ok a)
			(10,50) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Connection_close a b c d)
			(10,51) ->  return Connection_close_ok
			(20,10) -> get >>= \a ->  return (Channel_open a)
			(20,11) -> get >>= \a ->  return (Channel_open_ok a)
			(20,20) -> get >>= \a ->  return (Channel_flow a)
			(20,21) -> get >>= \a ->  return (Channel_flow_ok a)
			(20,40) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Channel_close a b c d)
			(20,41) ->  return Channel_close_ok
			(40,10) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 5 >>= \[d,e,f,g,h] -> get >>= \i ->  return (Exchange_declare a b c d e f g h i)
			(40,11) ->  return Exchange_declare_ok
			(40,20) -> get >>= \a -> get >>= \b -> getBits 2 >>= \[c,d] ->  return (Exchange_delete a b c d)
			(40,21) ->  return Exchange_delete_ok
			(40,30) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e -> get >>= \f ->  return (Exchange_bind a b c d e f)
			(40,31) ->  return Exchange_bind_ok
			(40,40) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e -> get >>= \f ->  return (Exchange_unbind a b c d e f)
			(40,51) ->  return Exchange_unbind_ok
			(50,10) -> get >>= \a -> get >>= \b -> getBits 5 >>= \[c,d,e,f,g] -> get >>= \h ->  return (Queue_declare a b c d e f g h)
			(50,11) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Queue_declare_ok a b c)
			(50,20) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e -> get >>= \f ->  return (Queue_bind a b c d e f)
			(50,21) ->  return Queue_bind_ok
			(50,50) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e ->  return (Queue_unbind a b c d e)
			(50,51) ->  return Queue_unbind_ok
			(50,30) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Queue_purge a b c)
			(50,31) -> get >>= \a ->  return (Queue_purge_ok a)
			(50,40) -> get >>= \a -> get >>= \b -> getBits 3 >>= \[c,d,e] ->  return (Queue_delete a b c d e)
			(50,41) -> get >>= \a ->  return (Queue_delete_ok a)
			(60,10) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Basic_qos a b c)
			(60,11) ->  return Basic_qos_ok
			(60,20) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 4 >>= \[d,e,f,g] -> get >>= \h ->  return (Basic_consume a b c d e f g h)
			(60,21) -> get >>= \a ->  return (Basic_consume_ok a)
			(60,30) -> get >>= \a -> get >>= \b ->  return (Basic_cancel a b)
			(60,31) -> get >>= \a ->  return (Basic_cancel_ok a)
			(60,40) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 2 >>= \[d,e] ->  return (Basic_publish a b c d e)
			(60,50) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Basic_return a b c d)
			(60,60) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e ->  return (Basic_deliver a b c d e)
			(60,70) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Basic_get a b c)
			(60,71) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e ->  return (Basic_get_ok a b c d e)
			(60,72) -> get >>= \a ->  return (Basic_get_empty a)
			(60,80) -> get >>= \a -> get >>= \b ->  return (Basic_ack a b)
			(60,90) -> get >>= \a -> get >>= \b ->  return (Basic_reject a b)
			(60,100) -> get >>= \a ->  return (Basic_recover_async a)
			(60,110) -> get >>= \a ->  return (Basic_recover a)
			(60,111) ->  return Basic_recover_ok
			(60,120) -> get >>= \a -> getBits 2 >>= \[b,c] ->  return (Basic_nack a b c)
			(90,10) ->  return Tx_select
			(90,11) ->  return Tx_select_ok
			(90,20) ->  return Tx_commit
			(90,21) ->  return Tx_commit_ok
			(90,30) ->  return Tx_rollback
			(90,31) ->  return Tx_rollback_ok
			(85,10) -> get >>= \a ->  return (Confirm_select a)
			(85,11) ->  return Confirm_select_ok
			x -> error ("Unexpected classID and methodID: " ++ show x)
data MethodPayload =

	Connection_start
		Octet -- version-major
		Octet -- version-minor
		FieldTable -- server-properties
		LongString -- mechanisms
		LongString -- locales
	|
	Connection_start_ok
		FieldTable -- client-properties
		ShortString -- mechanism
		LongString -- response
		ShortString -- locale
	|
	Connection_secure
		LongString -- challenge
	|
	Connection_secure_ok
		LongString -- response
	|
	Connection_tune
		ShortInt -- channel-max
		LongInt -- frame-max
		ShortInt -- heartbeat
	|
	Connection_tune_ok
		ShortInt -- channel-max
		LongInt -- frame-max
		ShortInt -- heartbeat
	|
	Connection_open
		ShortString -- virtual-host
		ShortString -- reserved-1
		Bit -- reserved-2
	|
	Connection_open_ok
		ShortString -- reserved-1
	|
	Connection_close
		ShortInt -- reply-code
		ShortString -- reply-text
		ShortInt -- class-id
		ShortInt -- method-id
	|
	Connection_close_ok

	|
	Channel_open
		ShortString -- reserved-1
	|
	Channel_open_ok
		LongString -- reserved-1
	|
	Channel_flow
		Bit -- active
	|
	Channel_flow_ok
		Bit -- active
	|
	Channel_close
		ShortInt -- reply-code
		ShortString -- reply-text
		ShortInt -- class-id
		ShortInt -- method-id
	|
	Channel_close_ok

	|
	Exchange_declare
		ShortInt -- reserved-1
		ShortString -- exchange
		ShortString -- typ
		Bit -- passive
		Bit -- durable
		Bit -- auto-delete
		Bit -- internal
		Bit -- no-wait
		FieldTable -- arguments
	|
	Exchange_declare_ok

	|
	Exchange_delete
		ShortInt -- reserved-1
		ShortString -- exchange
		Bit -- if-unused
		Bit -- no-wait
	|
	Exchange_delete_ok

	|
	Exchange_bind
		ShortInt -- reserved-1
		ShortString -- destination
		ShortString -- source
		ShortString -- routing-key
		Bit -- no-wait
		FieldTable -- arguments
	|
	Exchange_bind_ok

	|
	Exchange_unbind
		ShortInt -- reserved-1
		ShortString -- destination
		ShortString -- source
		ShortString -- routing-key
		Bit -- no-wait
		FieldTable -- arguments
	|
	Exchange_unbind_ok

	|
	Queue_declare
		ShortInt -- reserved-1
		ShortString -- queue
		Bit -- passive
		Bit -- durable
		Bit -- exclusive
		Bit -- auto-delete
		Bit -- no-wait
		FieldTable -- arguments
	|
	Queue_declare_ok
		ShortString -- queue
		LongInt -- message-count
		LongInt -- consumer-count
	|
	Queue_bind
		ShortInt -- reserved-1
		ShortString -- queue
		ShortString -- exchange
		ShortString -- routing-key
		Bit -- no-wait
		FieldTable -- arguments
	|
	Queue_bind_ok

	|
	Queue_unbind
		ShortInt -- reserved-1
		ShortString -- queue
		ShortString -- exchange
		ShortString -- routing-key
		FieldTable -- arguments
	|
	Queue_unbind_ok

	|
	Queue_purge
		ShortInt -- reserved-1
		ShortString -- queue
		Bit -- no-wait
	|
	Queue_purge_ok
		LongInt -- message-count
	|
	Queue_delete
		ShortInt -- reserved-1
		ShortString -- queue
		Bit -- if-unused
		Bit -- if-empty
		Bit -- no-wait
	|
	Queue_delete_ok
		LongInt -- message-count
	|
	Basic_qos
		LongInt -- prefetch-size
		ShortInt -- prefetch-count
		Bit -- global
	|
	Basic_qos_ok

	|
	Basic_consume
		ShortInt -- reserved-1
		ShortString -- queue
		ShortString -- consumer-tag
		Bit -- no-local
		Bit -- no-ack
		Bit -- exclusive
		Bit -- no-wait
		FieldTable -- arguments
	|
	Basic_consume_ok
		ShortString -- consumer-tag
	|
	Basic_cancel
		ShortString -- consumer-tag
		Bit -- no-wait
	|
	Basic_cancel_ok
		ShortString -- consumer-tag
	|
	Basic_publish
		ShortInt -- reserved-1
		ShortString -- exchange
		ShortString -- routing-key
		Bit -- mandatory
		Bit -- immediate
	|
	Basic_return
		ShortInt -- reply-code
		ShortString -- reply-text
		ShortString -- exchange
		ShortString -- routing-key
	|
	Basic_deliver
		ShortString -- consumer-tag
		LongLongInt -- delivery-tag
		Bit -- redelivered
		ShortString -- exchange
		ShortString -- routing-key
	|
	Basic_get
		ShortInt -- reserved-1
		ShortString -- queue
		Bit -- no-ack
	|
	Basic_get_ok
		LongLongInt -- delivery-tag
		Bit -- redelivered
		ShortString -- exchange
		ShortString -- routing-key
		LongInt -- message-count
	|
	Basic_get_empty
		ShortString -- reserved-1
	|
	Basic_ack
		LongLongInt -- delivery-tag
		Bit -- multiple
	|
	Basic_reject
		LongLongInt -- delivery-tag
		Bit -- requeue
	|
	Basic_recover_async
		Bit -- requeue
	|
	Basic_recover
		Bit -- requeue
	|
	Basic_recover_ok

	|
	Basic_nack
		LongLongInt -- delivery-tag
		Bit -- multiple
		Bit -- requeue
	|
	Tx_select

	|
	Tx_select_ok

	|
	Tx_commit

	|
	Tx_commit_ok

	|
	Tx_rollback

	|
	Tx_rollback_ok

	|
	Confirm_select
		Bit -- nowait
	|
	Confirm_select_ok


	deriving Show