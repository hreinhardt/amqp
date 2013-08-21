module Network.AMQP.Generated where

import Network.AMQP.Types
import Data.Maybe
import Data.Binary
import Data.Binary.Get
import Data.Binary.Put
import Data.Bits

getContentHeaderProperties :: ShortInt -> Get ContentHeaderProperties
getContentHeaderProperties 10 = getPropBits 0 >>= \[] ->  return CHConnection 
getContentHeaderProperties 20 = getPropBits 0 >>= \[] ->  return CHChannel 
getContentHeaderProperties 30 = getPropBits 0 >>= \[] ->  return CHAccess 
getContentHeaderProperties 40 = getPropBits 0 >>= \[] ->  return CHExchange 
getContentHeaderProperties 50 = getPropBits 0 >>= \[] ->  return CHQueue 
getContentHeaderProperties 60 = getPropBits 14 >>= \[a,b,c,d,e,f,g,h,i,j,k,l,m,n] -> condGet a >>= \a' -> condGet b >>= \b' -> condGet c >>= \c' -> condGet d >>= \d' -> condGet e >>= \e' -> condGet f >>= \f' -> condGet g >>= \g' -> condGet h >>= \h' -> condGet i >>= \i' -> condGet j >>= \j' -> condGet k >>= \k' -> condGet l >>= \l' -> condGet m >>= \m' -> condGet n >>= \n' ->  return (CHBasic a' b' c' d' e' f' g' h' i' j' k' l' m' n' )
getContentHeaderProperties 70 = getPropBits 9 >>= \[a,b,c,d,e,f,g,h,i] -> condGet a >>= \a' -> condGet b >>= \b' -> condGet c >>= \c' -> condGet d >>= \d' -> condGet e >>= \e' -> condGet f >>= \f' -> condGet g >>= \g' -> condGet h >>= \h' -> condGet i >>= \i' ->  return (CHFile a' b' c' d' e' f' g' h' i' )
getContentHeaderProperties 80 = getPropBits 5 >>= \[a,b,c,d,e] -> condGet a >>= \a' -> condGet b >>= \b' -> condGet c >>= \c' -> condGet d >>= \d' -> condGet e >>= \e' ->  return (CHStream a' b' c' d' e' )
getContentHeaderProperties 90 = getPropBits 0 >>= \[] ->  return CHTx 
getContentHeaderProperties 100 = getPropBits 0 >>= \[] ->  return CHDtx 
getContentHeaderProperties 110 = getPropBits 5 >>= \[a,b,c,d,e] -> condGet a >>= \a' -> condGet b >>= \b' -> condGet c >>= \c' -> condGet d >>= \d' -> condGet e >>= \e' ->  return (CHTunnel a' b' c' d' e' )
getContentHeaderProperties 120 = getPropBits 0 >>= \[] ->  return CHTest 

getContentHeaderProperties n = error ("Unexpected content header properties: " ++ show n)
putContentHeaderProperties :: ContentHeaderProperties -> Put
putContentHeaderProperties CHConnection = putPropBits [] 
putContentHeaderProperties CHChannel = putPropBits [] 
putContentHeaderProperties CHAccess = putPropBits [] 
putContentHeaderProperties CHExchange = putPropBits [] 
putContentHeaderProperties CHQueue = putPropBits [] 
putContentHeaderProperties (CHBasic a b c d e f g h i j k l m n) = putPropBits [isJust a,isJust b,isJust c,isJust d,isJust e,isJust f,isJust g,isJust h,isJust i,isJust j,isJust k,isJust l,isJust m,isJust n]  >> condPut a >> condPut b >> condPut c >> condPut d >> condPut e >> condPut f >> condPut g >> condPut h >> condPut i >> condPut j >> condPut k >> condPut l >> condPut m >> condPut n
putContentHeaderProperties (CHFile a b c d e f g h i) = putPropBits [isJust a,isJust b,isJust c,isJust d,isJust e,isJust f,isJust g,isJust h,isJust i]  >> condPut a >> condPut b >> condPut c >> condPut d >> condPut e >> condPut f >> condPut g >> condPut h >> condPut i
putContentHeaderProperties (CHStream a b c d e) = putPropBits [isJust a,isJust b,isJust c,isJust d,isJust e]  >> condPut a >> condPut b >> condPut c >> condPut d >> condPut e
putContentHeaderProperties CHTx = putPropBits [] 
putContentHeaderProperties CHDtx = putPropBits [] 
putContentHeaderProperties (CHTunnel a b c d e) = putPropBits [isJust a,isJust b,isJust c,isJust d,isJust e]  >> condPut a >> condPut b >> condPut c >> condPut d >> condPut e
putContentHeaderProperties CHTest = putPropBits [] 

getClassIDOf :: ContentHeaderProperties -> ShortInt
getClassIDOf (CHConnection) = 10
getClassIDOf (CHChannel) = 20
getClassIDOf (CHAccess) = 30
getClassIDOf (CHExchange) = 40
getClassIDOf (CHQueue) = 50
getClassIDOf (CHBasic _ _ _ _ _ _ _ _ _ _ _ _ _ _) = 60
getClassIDOf (CHFile _ _ _ _ _ _ _ _ _) = 70
getClassIDOf (CHStream _ _ _ _ _) = 80
getClassIDOf (CHTx) = 90
getClassIDOf (CHDtx) = 100
getClassIDOf (CHTunnel _ _ _ _ _) = 110
getClassIDOf (CHTest) = 120

data ContentHeaderProperties = 
	CHConnection
		
	|CHChannel
		
	|CHAccess
		
	|CHExchange
		
	|CHQueue
		
	|CHBasic
		(Maybe ShortString) -- content_type
		(Maybe ShortString) -- content_encoding
		(Maybe FieldTable) -- headers
		(Maybe Octet) -- delivery_mode
		(Maybe Octet) -- priority
		(Maybe ShortString) -- correlation_id
		(Maybe ShortString) -- reply_to
		(Maybe ShortString) -- expiration
		(Maybe ShortString) -- message_id
		(Maybe Timestamp) -- timestamp
		(Maybe ShortString) -- typ
		(Maybe ShortString) -- user_id
		(Maybe ShortString) -- app_id
		(Maybe ShortString) -- cluster_id
	|CHFile
		(Maybe ShortString) -- content_type
		(Maybe ShortString) -- content_encoding
		(Maybe FieldTable) -- headers
		(Maybe Octet) -- priority
		(Maybe ShortString) -- reply_to
		(Maybe ShortString) -- message_id
		(Maybe ShortString) -- filename
		(Maybe Timestamp) -- timestamp
		(Maybe ShortString) -- cluster_id
	|CHStream
		(Maybe ShortString) -- content_type
		(Maybe ShortString) -- content_encoding
		(Maybe FieldTable) -- headers
		(Maybe Octet) -- priority
		(Maybe Timestamp) -- timestamp
	|CHTx
		
	|CHDtx
		
	|CHTunnel
		(Maybe FieldTable) -- headers
		(Maybe ShortString) -- proxy_name
		(Maybe ShortString) -- data_name
		(Maybe Octet) -- durable
		(Maybe Octet) -- broadcast
	|CHTest
		

	deriving Show

--Bits need special handling because AMQP requires contiguous bits to be packed into a Word8
-- | Packs up to 8 bits into a Word8
putBits :: [Bit] -> Put
putBits xs = putWord8 $ putBits' 0 xs
putBits' :: Int -> [Bit] -> Word8
putBits' _ [] = 0
putBits' offset (x:xs) = (shiftL (toInt x) offset) .|. (putBits' (offset+1) xs)
    where toInt True = 1
          toInt False = 0
getBits :: Int -> Get [Bit]
getBits num = getWord8 >>= \x -> return $ getBits' num 0 x
getBits' :: Int -> Int -> Word8 -> [Bit]
getBits' 0 _ _ = []
getBits' num offset x = ((x .&. (2^offset)) /= 0) : (getBits' (num-1) (offset+1) x)
-- | Packs up to 15 Bits into a Word16 (=Property Flags) 
putPropBits :: [Bit] -> Put
putPropBits xs = putWord16be $ (putPropBits' 0 xs) 
putPropBits' :: Int -> [Bit] -> Word16
putPropBits' _ [] = 0
putPropBits' offset (x:xs) = (shiftL (toInt x) (15-offset)) .|. (putPropBits' (offset+1) xs)
    where toInt True = 1
          toInt False = 0
getPropBits :: Int -> Get [Bit]
getPropBits num = getWord16be >>= \x -> return $ getPropBits' num 0 x
getPropBits' :: Int -> Int -> Word16 -> [Bit]
getPropBits' 0 _ _ = []
getPropBits' num offset x = ((x .&. (2^(15-offset))) /= 0) : (getPropBits' (num-1) (offset+1) x)
condGet :: Binary a => Bool -> Get (Maybe a)
condGet False = return Nothing
condGet True = get >>= \x -> return $ Just x

condPut :: Binary a => Maybe a -> Put
condPut (Just x) = put x
condPut _ = return ()

instance Binary MethodPayload where
	put (Connection_start a b c d e) = putWord16be 10 >> putWord16be 10 >> put a >> put b >> put c >> put d >> put e
	put (Connection_start_ok a b c d) = putWord16be 10 >> putWord16be 11 >> put a >> put b >> put c >> put d
	put (Connection_secure a) = putWord16be 10 >> putWord16be 20 >> put a
	put (Connection_secure_ok a) = putWord16be 10 >> putWord16be 21 >> put a
	put (Connection_tune a b c) = putWord16be 10 >> putWord16be 30 >> put a >> put b >> put c
	put (Connection_tune_ok a b c) = putWord16be 10 >> putWord16be 31 >> put a >> put b >> put c
	put (Connection_open a b c) = putWord16be 10 >> putWord16be 40 >> put a >> put b >> put c
	put (Connection_open_ok a) = putWord16be 10 >> putWord16be 41 >> put a
	put (Connection_redirect a b) = putWord16be 10 >> putWord16be 50 >> put a >> put b
	put (Connection_close a b c d) = putWord16be 10 >> putWord16be 60 >> put a >> put b >> put c >> put d
	put Connection_close_ok = putWord16be 10 >> putWord16be 61
	put (Channel_open a) = putWord16be 20 >> putWord16be 10 >> put a
	put Channel_open_ok = putWord16be 20 >> putWord16be 11
	put (Channel_flow a) = putWord16be 20 >> putWord16be 20 >> put a
	put (Channel_flow_ok a) = putWord16be 20 >> putWord16be 21 >> put a
	put (Channel_alert a b c) = putWord16be 20 >> putWord16be 30 >> put a >> put b >> put c
	put (Channel_close a b c d) = putWord16be 20 >> putWord16be 40 >> put a >> put b >> put c >> put d
	put Channel_close_ok = putWord16be 20 >> putWord16be 41
	put (Access_request a b c d e f) = putWord16be 30 >> putWord16be 10 >> put a >> putBits [b,c,d,e,f]
	put (Access_request_ok a) = putWord16be 30 >> putWord16be 11 >> put a
	put (Exchange_declare a b c d e f g h i) = putWord16be 40 >> putWord16be 10 >> put a >> put b >> put c >> putBits [d,e,f,g,h] >> put i
	put Exchange_declare_ok = putWord16be 40 >> putWord16be 11
	put (Exchange_delete a b c d) = putWord16be 40 >> putWord16be 20 >> put a >> put b >> putBits [c,d]
	put Exchange_delete_ok = putWord16be 40 >> putWord16be 21
	put (Queue_declare a b c d e f g h) = putWord16be 50 >> putWord16be 10 >> put a >> put b >> putBits [c,d,e,f,g] >> put h
	put (Queue_declare_ok a b c) = putWord16be 50 >> putWord16be 11 >> put a >> put b >> put c
	put (Queue_bind a b c d e f) = putWord16be 50 >> putWord16be 20 >> put a >> put b >> put c >> put d >> put e >> put f
	put Queue_bind_ok = putWord16be 50 >> putWord16be 21
	put (Queue_purge a b c) = putWord16be 50 >> putWord16be 30 >> put a >> put b >> put c
	put (Queue_purge_ok a) = putWord16be 50 >> putWord16be 31 >> put a
	put (Queue_delete a b c d e) = putWord16be 50 >> putWord16be 40 >> put a >> put b >> putBits [c,d,e]
	put (Queue_delete_ok a) = putWord16be 50 >> putWord16be 41 >> put a
	put (Basic_qos a b c) = putWord16be 60 >> putWord16be 10 >> put a >> put b >> put c
	put Basic_qos_ok = putWord16be 60 >> putWord16be 11
	put (Basic_consume a b c d e f g) = putWord16be 60 >> putWord16be 20 >> put a >> put b >> put c >> putBits [d,e,f,g]
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
	put (Basic_recover a) = putWord16be 60 >> putWord16be 100 >> put a
	put (File_qos a b c) = putWord16be 70 >> putWord16be 10 >> put a >> put b >> put c
	put File_qos_ok = putWord16be 70 >> putWord16be 11
	put (File_consume a b c d e f g) = putWord16be 70 >> putWord16be 20 >> put a >> put b >> put c >> putBits [d,e,f,g]
	put (File_consume_ok a) = putWord16be 70 >> putWord16be 21 >> put a
	put (File_cancel a b) = putWord16be 70 >> putWord16be 30 >> put a >> put b
	put (File_cancel_ok a) = putWord16be 70 >> putWord16be 31 >> put a
	put (File_open a b) = putWord16be 70 >> putWord16be 40 >> put a >> put b
	put (File_open_ok a) = putWord16be 70 >> putWord16be 41 >> put a
	put File_stage = putWord16be 70 >> putWord16be 50
	put (File_publish a b c d e f) = putWord16be 70 >> putWord16be 60 >> put a >> put b >> put c >> putBits [d,e] >> put f
	put (File_return a b c d) = putWord16be 70 >> putWord16be 70 >> put a >> put b >> put c >> put d
	put (File_deliver a b c d e f) = putWord16be 70 >> putWord16be 80 >> put a >> put b >> put c >> put d >> put e >> put f
	put (File_ack a b) = putWord16be 70 >> putWord16be 90 >> put a >> put b
	put (File_reject a b) = putWord16be 70 >> putWord16be 100 >> put a >> put b
	put (Stream_qos a b c d) = putWord16be 80 >> putWord16be 10 >> put a >> put b >> put c >> put d
	put Stream_qos_ok = putWord16be 80 >> putWord16be 11
	put (Stream_consume a b c d e f) = putWord16be 80 >> putWord16be 20 >> put a >> put b >> put c >> putBits [d,e,f]
	put (Stream_consume_ok a) = putWord16be 80 >> putWord16be 21 >> put a
	put (Stream_cancel a b) = putWord16be 80 >> putWord16be 30 >> put a >> put b
	put (Stream_cancel_ok a) = putWord16be 80 >> putWord16be 31 >> put a
	put (Stream_publish a b c d e) = putWord16be 80 >> putWord16be 40 >> put a >> put b >> put c >> putBits [d,e]
	put (Stream_return a b c d) = putWord16be 80 >> putWord16be 50 >> put a >> put b >> put c >> put d
	put (Stream_deliver a b c d) = putWord16be 80 >> putWord16be 60 >> put a >> put b >> put c >> put d
	put Tx_select = putWord16be 90 >> putWord16be 10
	put Tx_select_ok = putWord16be 90 >> putWord16be 11
	put Tx_commit = putWord16be 90 >> putWord16be 20
	put Tx_commit_ok = putWord16be 90 >> putWord16be 21
	put Tx_rollback = putWord16be 90 >> putWord16be 30
	put Tx_rollback_ok = putWord16be 90 >> putWord16be 31
	put Dtx_select = putWord16be 100 >> putWord16be 10
	put Dtx_select_ok = putWord16be 100 >> putWord16be 11
	put (Dtx_start a) = putWord16be 100 >> putWord16be 20 >> put a
	put Dtx_start_ok = putWord16be 100 >> putWord16be 21
	put (Tunnel_request a) = putWord16be 110 >> putWord16be 10 >> put a
	put (Test_integer a b c d e) = putWord16be 120 >> putWord16be 10 >> put a >> put b >> put c >> put d >> put e
	put (Test_integer_ok a) = putWord16be 120 >> putWord16be 11 >> put a
	put (Test_string a b c) = putWord16be 120 >> putWord16be 20 >> put a >> put b >> put c
	put (Test_string_ok a) = putWord16be 120 >> putWord16be 21 >> put a
	put (Test_table a b c) = putWord16be 120 >> putWord16be 30 >> put a >> put b >> put c
	put (Test_table_ok a b) = putWord16be 120 >> putWord16be 31 >> put a >> put b
	put Test_content = putWord16be 120 >> putWord16be 40
	put (Test_content_ok a) = putWord16be 120 >> putWord16be 41 >> put a
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
			(10,50) -> get >>= \a -> get >>= \b ->  return (Connection_redirect a b)
			(10,60) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Connection_close a b c d)
			(10,61) ->  return Connection_close_ok
			(20,10) -> get >>= \a ->  return (Channel_open a)
			(20,11) ->  return Channel_open_ok
			(20,20) -> get >>= \a ->  return (Channel_flow a)
			(20,21) -> get >>= \a ->  return (Channel_flow_ok a)
			(20,30) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Channel_alert a b c)
			(20,40) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Channel_close a b c d)
			(20,41) ->  return Channel_close_ok
			(30,10) -> get >>= \a -> getBits 5 >>= \[b,c,d,e,f] ->  return (Access_request a b c d e f)
			(30,11) -> get >>= \a ->  return (Access_request_ok a)
			(40,10) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 5 >>= \[d,e,f,g,h] -> get >>= \i ->  return (Exchange_declare a b c d e f g h i)
			(40,11) ->  return Exchange_declare_ok
			(40,20) -> get >>= \a -> get >>= \b -> getBits 2 >>= \[c,d] ->  return (Exchange_delete a b c d)
			(40,21) ->  return Exchange_delete_ok
			(50,10) -> get >>= \a -> get >>= \b -> getBits 5 >>= \[c,d,e,f,g] -> get >>= \h ->  return (Queue_declare a b c d e f g h)
			(50,11) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Queue_declare_ok a b c)
			(50,20) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e -> get >>= \f ->  return (Queue_bind a b c d e f)
			(50,21) ->  return Queue_bind_ok
			(50,30) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Queue_purge a b c)
			(50,31) -> get >>= \a ->  return (Queue_purge_ok a)
			(50,40) -> get >>= \a -> get >>= \b -> getBits 3 >>= \[c,d,e] ->  return (Queue_delete a b c d e)
			(50,41) -> get >>= \a ->  return (Queue_delete_ok a)
			(60,10) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Basic_qos a b c)
			(60,11) ->  return Basic_qos_ok
			(60,20) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 4 >>= \[d,e,f,g] ->  return (Basic_consume a b c d e f g)
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
			(60,100) -> get >>= \a ->  return (Basic_recover a)
			(70,10) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (File_qos a b c)
			(70,11) ->  return File_qos_ok
			(70,20) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 4 >>= \[d,e,f,g] ->  return (File_consume a b c d e f g)
			(70,21) -> get >>= \a ->  return (File_consume_ok a)
			(70,30) -> get >>= \a -> get >>= \b ->  return (File_cancel a b)
			(70,31) -> get >>= \a ->  return (File_cancel_ok a)
			(70,40) -> get >>= \a -> get >>= \b ->  return (File_open a b)
			(70,41) -> get >>= \a ->  return (File_open_ok a)
			(70,50) ->  return File_stage
			(70,60) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 2 >>= \[d,e] -> get >>= \f ->  return (File_publish a b c d e f)
			(70,70) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (File_return a b c d)
			(70,80) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e -> get >>= \f ->  return (File_deliver a b c d e f)
			(70,90) -> get >>= \a -> get >>= \b ->  return (File_ack a b)
			(70,100) -> get >>= \a -> get >>= \b ->  return (File_reject a b)
			(80,10) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Stream_qos a b c d)
			(80,11) ->  return Stream_qos_ok
			(80,20) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 3 >>= \[d,e,f] ->  return (Stream_consume a b c d e f)
			(80,21) -> get >>= \a ->  return (Stream_consume_ok a)
			(80,30) -> get >>= \a -> get >>= \b ->  return (Stream_cancel a b)
			(80,31) -> get >>= \a ->  return (Stream_cancel_ok a)
			(80,40) -> get >>= \a -> get >>= \b -> get >>= \c -> getBits 2 >>= \[d,e] ->  return (Stream_publish a b c d e)
			(80,50) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Stream_return a b c d)
			(80,60) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d ->  return (Stream_deliver a b c d)
			(90,10) ->  return Tx_select
			(90,11) ->  return Tx_select_ok
			(90,20) ->  return Tx_commit
			(90,21) ->  return Tx_commit_ok
			(90,30) ->  return Tx_rollback
			(90,31) ->  return Tx_rollback_ok
			(100,10) ->  return Dtx_select
			(100,11) ->  return Dtx_select_ok
			(100,20) -> get >>= \a ->  return (Dtx_start a)
			(100,21) ->  return Dtx_start_ok
			(110,10) -> get >>= \a ->  return (Tunnel_request a)
			(120,10) -> get >>= \a -> get >>= \b -> get >>= \c -> get >>= \d -> get >>= \e ->  return (Test_integer a b c d e)
			(120,11) -> get >>= \a ->  return (Test_integer_ok a)
			(120,20) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Test_string a b c)
			(120,21) -> get >>= \a ->  return (Test_string_ok a)
			(120,30) -> get >>= \a -> get >>= \b -> get >>= \c ->  return (Test_table a b c)
			(120,31) -> get >>= \a -> get >>= \b ->  return (Test_table_ok a b)
			(120,40) ->  return Test_content
			(120,41) -> get >>= \a ->  return (Test_content_ok a)
			x -> error ("Unexpected classID and methodID: " ++ show x)
data MethodPayload = 

	Connection_start
		Octet -- version_major
		Octet -- version_minor
		FieldTable -- server_properties
		LongString -- mechanisms
		LongString -- locales
	|
	Connection_start_ok
		FieldTable -- client_properties
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
		ShortInt -- channel_max
		LongInt -- frame_max
		ShortInt -- heartbeat
	|
	Connection_tune_ok
		ShortInt -- channel_max
		LongInt -- frame_max
		ShortInt -- heartbeat
	|
	Connection_open
		ShortString -- virtual_host
		ShortString -- capabilities
		Bit -- insist
	|
	Connection_open_ok
		ShortString -- known_hosts
	|
	Connection_redirect
		ShortString -- host
		ShortString -- known_hosts
	|
	Connection_close
		ShortInt -- reply_code
		ShortString -- reply_text
		ShortInt -- class_id
		ShortInt -- method_id
	|
	Connection_close_ok
		
	|
	Channel_open
		ShortString -- out_of_band
	|
	Channel_open_ok
		
	|
	Channel_flow
		Bit -- active
	|
	Channel_flow_ok
		Bit -- active
	|
	Channel_alert
		ShortInt -- reply_code
		ShortString -- reply_text
		FieldTable -- details
	|
	Channel_close
		ShortInt -- reply_code
		ShortString -- reply_text
		ShortInt -- class_id
		ShortInt -- method_id
	|
	Channel_close_ok
		
	|
	Access_request
		ShortString -- realm
		Bit -- exclusive
		Bit -- passive
		Bit -- active
		Bit -- write
		Bit -- read
	|
	Access_request_ok
		ShortInt -- ticket
	|
	Exchange_declare
		ShortInt -- ticket
		ShortString -- exchange
		ShortString -- typ
		Bit -- passive
		Bit -- durable
		Bit -- auto_delete
		Bit -- internal
		Bit -- nowait
		FieldTable -- arguments
	|
	Exchange_declare_ok
		
	|
	Exchange_delete
		ShortInt -- ticket
		ShortString -- exchange
		Bit -- if_unused
		Bit -- nowait
	|
	Exchange_delete_ok
		
	|
	Queue_declare
		ShortInt -- ticket
		ShortString -- queue
		Bit -- passive
		Bit -- durable
		Bit -- exclusive
		Bit -- auto_delete
		Bit -- nowait
		FieldTable -- arguments
	|
	Queue_declare_ok
		ShortString -- queue
		LongInt -- message_count
		LongInt -- consumer_count
	|
	Queue_bind
		ShortInt -- ticket
		ShortString -- queue
		ShortString -- exchange
		ShortString -- routing_key
		Bit -- nowait
		FieldTable -- arguments
	|
	Queue_bind_ok
		
	|
	Queue_purge
		ShortInt -- ticket
		ShortString -- queue
		Bit -- nowait
	|
	Queue_purge_ok
		LongInt -- message_count
	|
	Queue_delete
		ShortInt -- ticket
		ShortString -- queue
		Bit -- if_unused
		Bit -- if_empty
		Bit -- nowait
	|
	Queue_delete_ok
		LongInt -- message_count
	|
	Basic_qos
		LongInt -- prefetch_size
		ShortInt -- prefetch_count
		Bit -- global
	|
	Basic_qos_ok
		
	|
	Basic_consume
		ShortInt -- ticket
		ShortString -- queue
		ShortString -- consumer_tag
		Bit -- no_local
		Bit -- no_ack
		Bit -- exclusive
		Bit -- nowait
	|
	Basic_consume_ok
		ShortString -- consumer_tag
	|
	Basic_cancel
		ShortString -- consumer_tag
		Bit -- nowait
	|
	Basic_cancel_ok
		ShortString -- consumer_tag
	|
	Basic_publish
		ShortInt -- ticket
		ShortString -- exchange
		ShortString -- routing_key
		Bit -- mandatory
		Bit -- immediate
	|
	Basic_return
		ShortInt -- reply_code
		ShortString -- reply_text
		ShortString -- exchange
		ShortString -- routing_key
	|
	Basic_deliver
		ShortString -- consumer_tag
		LongLongInt -- delivery_tag
		Bit -- redelivered
		ShortString -- exchange
		ShortString -- routing_key
	|
	Basic_get
		ShortInt -- ticket
		ShortString -- queue
		Bit -- no_ack
	|
	Basic_get_ok
		LongLongInt -- delivery_tag
		Bit -- redelivered
		ShortString -- exchange
		ShortString -- routing_key
		LongInt -- message_count
	|
	Basic_get_empty
		ShortString -- cluster_id
	|
	Basic_ack
		LongLongInt -- delivery_tag
		Bit -- multiple
	|
	Basic_reject
		LongLongInt -- delivery_tag
		Bit -- requeue
	|
	Basic_recover
		Bit -- requeue
	|
	File_qos
		LongInt -- prefetch_size
		ShortInt -- prefetch_count
		Bit -- global
	|
	File_qos_ok
		
	|
	File_consume
		ShortInt -- ticket
		ShortString -- queue
		ShortString -- consumer_tag
		Bit -- no_local
		Bit -- no_ack
		Bit -- exclusive
		Bit -- nowait
	|
	File_consume_ok
		ShortString -- consumer_tag
	|
	File_cancel
		ShortString -- consumer_tag
		Bit -- nowait
	|
	File_cancel_ok
		ShortString -- consumer_tag
	|
	File_open
		ShortString -- identifier
		LongLongInt -- content_size
	|
	File_open_ok
		LongLongInt -- staged_size
	|
	File_stage
		
	|
	File_publish
		ShortInt -- ticket
		ShortString -- exchange
		ShortString -- routing_key
		Bit -- mandatory
		Bit -- immediate
		ShortString -- identifier
	|
	File_return
		ShortInt -- reply_code
		ShortString -- reply_text
		ShortString -- exchange
		ShortString -- routing_key
	|
	File_deliver
		ShortString -- consumer_tag
		LongLongInt -- delivery_tag
		Bit -- redelivered
		ShortString -- exchange
		ShortString -- routing_key
		ShortString -- identifier
	|
	File_ack
		LongLongInt -- delivery_tag
		Bit -- multiple
	|
	File_reject
		LongLongInt -- delivery_tag
		Bit -- requeue
	|
	Stream_qos
		LongInt -- prefetch_size
		ShortInt -- prefetch_count
		LongInt -- consume_rate
		Bit -- global
	|
	Stream_qos_ok
		
	|
	Stream_consume
		ShortInt -- ticket
		ShortString -- queue
		ShortString -- consumer_tag
		Bit -- no_local
		Bit -- exclusive
		Bit -- nowait
	|
	Stream_consume_ok
		ShortString -- consumer_tag
	|
	Stream_cancel
		ShortString -- consumer_tag
		Bit -- nowait
	|
	Stream_cancel_ok
		ShortString -- consumer_tag
	|
	Stream_publish
		ShortInt -- ticket
		ShortString -- exchange
		ShortString -- routing_key
		Bit -- mandatory
		Bit -- immediate
	|
	Stream_return
		ShortInt -- reply_code
		ShortString -- reply_text
		ShortString -- exchange
		ShortString -- routing_key
	|
	Stream_deliver
		ShortString -- consumer_tag
		LongLongInt -- delivery_tag
		ShortString -- exchange
		ShortString -- queue
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
	Dtx_select
		
	|
	Dtx_select_ok
		
	|
	Dtx_start
		ShortString -- dtx_identifier
	|
	Dtx_start_ok
		
	|
	Tunnel_request
		FieldTable -- meta_data
	|
	Test_integer
		Octet -- integer_1
		ShortInt -- integer_2
		LongInt -- integer_3
		LongLongInt -- integer_4
		Octet -- operation
	|
	Test_integer_ok
		LongLongInt -- result
	|
	Test_string
		ShortString -- string_1
		LongString -- string_2
		Octet -- operation
	|
	Test_string_ok
		LongString -- result
	|
	Test_table
		FieldTable -- table
		Octet -- integer_op
		Octet -- string_op
	|
	Test_table_ok
		LongLongInt -- integer_result
		LongString -- string_result
	|
	Test_content
		
	|
	Test_content_ok
		LongInt -- content_checksum

	deriving Show