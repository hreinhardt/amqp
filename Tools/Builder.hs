{-# LANGUAGE BangPatterns #-}
--reads the AMQP xml spec file and builds the "Generated.hs" module
--this is pretty much a BIG HACK

import Data.Char
import Data.Maybe

import Text.XML.Light

import qualified Data.Map as M
import qualified Data.List as L

data Class = Class String Int [Method] [Field] --className, classID, methods, content-fields
    deriving Show
data Method = Method String Int [Field] --methodName, methodID, fields
    deriving Show
data Field = TypeField String String --fieldName, fieldType
           | DomainField String String --fieldName, domainName
    deriving Show

fieldType :: M.Map String String -> Field -> String
fieldType _ (TypeField _ x) = x
fieldType domainMap (DomainField _ domain) = fromJust $ M.lookup domain domainMap

main :: IO ()
main = do
    spec <- readFile "amqp0-9-1.xml"
    let parsed = parseXML spec
    let !(Elem e) = parsed!!2

    -- read domains
    let domains = findChildren (unqual "domain") e

    --map from domainName => type
    let domainMap = M.fromList $ map readDomain domains

    -- read classes
    let classes = map readClass $ findChildren (unqual "class") e :: [Class]

    -- generate data declaration
    let dataDecl = "data MethodPayload = \n" ++ (concat $ L.intersperse "\t|" $ concatMap (writeDataDeclForClass domainMap) classes) ++ "\n\tderiving Show"

    -- generate binary instances for data-type
    let binaryGetInst = concat $ map ("\t"++) $ concatMap (writeBinaryGetInstForClass domainMap) classes
    let binaryPutInst = concat $ map ("\t"++) $ concatMap (writeBinaryPutInstForClass domainMap) classes

    -- generate content types
    let contentHeaders = concat $ L.intersperse "\t|" $ map (writeContentHeaderForClass domainMap) classes
    let contentHeadersGetInst = concatMap writeContentHeaderGetInstForClass classes
    let contentHeadersPutInst = concatMap writeContentHeaderPutInstForClass classes
    let contentHeadersClassIDs = concatMap writeContentHeaderClassIDsForClass classes

    writeFile "Generated.hs" (
        "module Network.AMQP.Generated where\n\n" ++
        "import Data.Binary\n" ++
        "import Data.Binary.Get\n" ++
        "import Data.Binary.Put\n" ++
        "import Data.Bits\n" ++
        "import Data.Maybe\n" ++
        "import Network.AMQP.Types\n\n" ++

        "getContentHeaderProperties :: ShortInt -> Get ContentHeaderProperties" ++ "\n" ++
        contentHeadersGetInst ++ "\n" ++
        "getContentHeaderProperties n = error (\"Unexpected content header properties: \" ++ show n)" ++ "\n" ++

        "putContentHeaderProperties :: ContentHeaderProperties -> Put" ++ "\n" ++
        contentHeadersPutInst ++ "\n" ++

        "getClassIDOf :: ContentHeaderProperties -> ShortInt" ++ "\n" ++
        contentHeadersClassIDs ++ "\n" ++

        "data ContentHeaderProperties = \n\t" ++
        contentHeaders ++
        "\n\tderiving Show\n\n" ++

        "--Bits need special handling because AMQP requires contiguous bits to be packed into a Word8\n" ++
        "-- | Packs up to 8 bits into a Word8\n" ++
        "putBits :: [Bit] -> Put\n" ++
        "putBits = putWord8 . putBits' 0\n" ++

        "putBits' :: Int -> [Bit] -> Word8\n" ++
        "putBits' _ [] = 0\n" ++
        "putBits' offset (x:xs) = (shiftL (toInt x) offset) .|. (putBits' (offset+1) xs)\n" ++
        "    where toInt True = 1\n" ++
        "          toInt False = 0\n" ++

        "getBits :: Int -> Get [Bit]\n" ++
        "getBits num = getWord8 >>= return . getBits' num 0\n" ++

        "getBits' :: Int -> Int -> Word8 -> [Bit]\n" ++
        "getBits' 0 _ _ = []\n" ++
        "getBits' num offset x = ((x .&. (2^offset)) /= 0) : (getBits' (num-1) (offset+1) x)\n" ++

        "-- | Packs up to 15 Bits into a Word16 (=Property Flags) \n" ++
        "putPropBits :: [Bit] -> Put\n" ++
        "putPropBits = putWord16be . putPropBits' 0\n" ++

        "putPropBits' :: Int -> [Bit] -> Word16\n" ++
        "putPropBits' _ [] = 0\n" ++
        "putPropBits' offset (x:xs) = (shiftL (toInt x) (15-offset)) .|. (putPropBits' (offset+1) xs)\n" ++
        "    where toInt True = 1\n" ++
        "          toInt False = 0\n" ++

        "getPropBits :: Int -> Get [Bit]\n" ++
        "getPropBits num = getWord16be >>= return . getPropBits' num 0\n" ++

        "getPropBits' :: Int -> Int -> Word16 -> [Bit]\n" ++
        "getPropBits' 0 _ _ = []\n" ++
        "getPropBits' num offset x = ((x .&. (2^(15-offset))) /= 0) : (getPropBits' (num-1) (offset+1) x)\n"++

        "condGet :: Binary a => Bool -> Get (Maybe a)\n" ++
        "condGet False = return Nothing\n" ++
        "condGet True = get >>= return . Just\n\n" ++

        "condPut :: Binary a => Maybe a -> Put\n" ++
        "condPut = maybe (return ()) put\n" ++

        "instance Binary MethodPayload where\n" ++

        -- put instances
        binaryPutInst ++

        -- get instances
        "\tget = do\n" ++
        "\t\tclassID <- getWord16be\n" ++
        "\t\tmethodID <- getWord16be\n" ++
        "\t\tcase (classID, methodID) of\n" ++
        binaryGetInst ++
        "\t\t\tx -> error (\"Unexpected classID and methodID: \" ++ show x)" ++ "\n" ++

        -- data declaration
        dataDecl)

translateType :: String -> String
translateType "octet" = "Octet"
translateType "longstr" = "LongString"
translateType "shortstr" = "ShortString"
translateType "short" = "ShortInt"
translateType "long" = "LongInt"
translateType "bit" = "Bit"
translateType "table" = "FieldTable"
translateType "longlong" = "LongLongInt"
translateType "timestamp" = "Timestamp"
translateType x = error x

fixClassName :: String -> String
fixClassName s = (toUpper $ head s) : (tail s)

fixMethodName :: String -> String
fixMethodName s = map f s
    where
        f '-' = '_'
        f x = x

fixFieldName :: String -> String
fixFieldName "type" = "typ"
fixFieldName s = map f s
    where
        f ' ' = '_'
        f x = x

---- data declaration ----

writeDataDeclForClass :: M.Map String String -> Class -> [String]
writeDataDeclForClass domainMap (Class nam _ methods _) =
    map ("\n\t" ++)  $ map (writeDataDeclForMethod domainMap nam) methods

writeDataDeclForMethod :: M.Map String String -> String -> Method -> String
writeDataDeclForMethod domainMap className (Method nam _ fields) =
    let fullName = (fixClassName className) ++ "_" ++ (fixMethodName nam) in
    --data type declaration
    (writeTypeDecl domainMap fullName fields)
    --binary instances
    --(writeBinaryInstance fullName fields)

writeTypeDecl :: M.Map String String -> String -> [Field] -> String
writeTypeDecl domainMap fullName fields =
    fullName ++ "\n\t\t" ++ (concat $ L.intersperse "\n\t\t" $ map writeF fields) ++ "\n"
  where
    writeF (TypeField nam typ) = (translateType typ) ++ " -- " ++ (fixFieldName nam)
    writeF f@(DomainField nam _) = (translateType $ fieldType domainMap f) ++ " -- " ++ (fixFieldName nam)

---- binary get instance ----

writeBinaryGetInstForClass :: M.Map String String -> Class -> [String]
writeBinaryGetInstForClass domainMap (Class nam index methods _) =
    map (writeBinaryGetInstForMethod domainMap nam index) methods

writeBinaryGetInstForMethod :: M.Map String String -> String -> Int -> Method -> String
writeBinaryGetInstForMethod domainMap className classIndex (Method nam index fields) =
    let fullName = (fixClassName className) ++ "_" ++ (fixMethodName nam) in
    --binary instances
    "\t" ++ (writeBinaryGetInstance domainMap fullName classIndex index fields)

writeBinaryGetInstance :: M.Map String String -> String -> Int -> Int -> [Field] -> String
writeBinaryGetInstance domainMap fullName classIndex methodIndex fields =
    "\t(" ++ (show classIndex) ++ "," ++ (show methodIndex) ++ ") -> " ++ getDef ++ "\n"
    where
        manyLetters = map (:[]) ['a'..'z']

        fieldTypes :: [(String,String)] --(a..z, fieldType)
        fieldTypes = zip manyLetters $ map (fieldType domainMap) fields

        --consecutive BITS have to be merged into a Word8
        --TODO: more than 8bits have to be split into several Word8
        grouped :: [ [(String, String)] ]
        grouped = L.groupBy (\(_,x) (_,y) -> x=="bit" && y=="bit") fieldTypes

        --concatMap (\x -> " get >>= \\" ++ x ++ " ->") (take (length fields) manyLetters)

        showBlob xs | length xs == 1 =  "get >>= \\" ++ (fst $ xs!!0) ++ " -> "
        showBlob xs = "getBits " ++ (show $ length xs) ++ " >>= \\[" ++ (concat $ L.intersperse "," $ map fst xs) ++ "] -> "

        getStmt = concatMap showBlob grouped

        getDef =
            let wrap = if (length fields) /= 0 then ("("++) . (++")") else id
            in
            getStmt
            ++ " return "
            ++ wrap (fullName ++ concatMap (" "++) (take (length fields) manyLetters))

---- binary put instance ----

writeBinaryPutInstForClass :: M.Map String String -> Class -> [String]
writeBinaryPutInstForClass domainMap (Class nam index methods _) =
    map (writeBinaryPutInstForMethod domainMap nam index) methods

writeBinaryPutInstForMethod :: M.Map String String -> String -> Int -> Method -> String
writeBinaryPutInstForMethod domainMap className classIndex (Method nam index fields) =
    let fullName = (fixClassName className) ++ "_" ++ (fixMethodName nam) in
    --binary instances
    (writeBinaryPutInstance domainMap fullName classIndex index fields)

writeBinaryPutInstance :: M.Map String String -> String -> Int -> Int -> [Field] -> String
writeBinaryPutInstance domainMap fullName classIndex methodIndex fields =
    putDef ++ "\n"
    where
        manyLetters = map (:[]) ['a'..'z']

        fieldTypes :: [(String,String)] --(a..z, fieldType)
        fieldTypes = zip manyLetters $ map (fieldType domainMap) fields

        --consecutive BITS have to be merged into a Word8
        --TODO: more than 8bits have to be split into several Word8
        grouped :: [ [(String, String)] ]
        grouped = L.groupBy (\(_,x) (_,y) -> x=="bit" && y=="bit") fieldTypes

        showBlob xs | length xs == 1 =  " >> put " ++ (fst $ xs!!0)
        showBlob xs = " >> putBits [" ++ (concat $ L.intersperse "," $ map fst xs) ++ "]"

        putStmt = concatMap showBlob grouped

        putDef =
            let wrap = if (length fields) /= 0 then ("("++) . (++")") else id
                pattern = fullName ++ concatMap (' ':) (take (length fields) manyLetters)
            in
                "put " ++ wrap pattern ++" = "
                ++ "putWord16be " ++ (show classIndex) ++ " >> putWord16be " ++ (show methodIndex)
                ++ putStmt

---- content header declaration ----

writeContentHeaderForClass :: M.Map String String -> Class -> String
writeContentHeaderForClass domainMap (Class nam _ _ fields) =
    let fullName = "CH" ++ (fixClassName nam) in
    (writeContentHeaderDecl domainMap fullName fields)

writeContentHeaderDecl :: M.Map String String -> String -> [Field] -> String
writeContentHeaderDecl domainMap fullName fields =
    fullName ++ "\n\t\t" ++ (concat $ L.intersperse "\n\t\t" $ map writeF fields) ++ "\n"
  where
    writeF (TypeField nam typ) = "(Maybe " ++ (translateType typ) ++ ") -- " ++ (fixFieldName nam)
    writeF f@(DomainField nam _) = "(Maybe " ++ (translateType $ fieldType domainMap f) ++ ") -- " ++ (fixFieldName nam)

---- contentheader get instance ----

writeContentHeaderGetInstForClass :: Class -> String
writeContentHeaderGetInstForClass (Class nam index _ fields) =
    let fullName = "CH" ++ (fixClassName nam) in
    --binary instances
    (writeContentHeaderGetInstance fullName index fields)

writeContentHeaderGetInstance :: String -> Int -> [Field] -> String
writeContentHeaderGetInstance fullName classIndex fields =
    "getContentHeaderProperties " ++ (show classIndex) ++ " = " ++ getDef ++ "\n"
    where
        manyLetters = map (:[]) ['a'..'z']
        usedLetters = take (length fields) manyLetters

        showBlob x =  "condGet " ++ x ++ " >>= \\" ++ x ++ "' -> "

        getStmt = concatMap showBlob usedLetters

        getDef =
            let wrap = if (length fields) /= 0 then ("("++) . (++")") else id
            in
            "getPropBits " ++ (show $ length fields)  ++ " >>= \\[" ++ (concat $ L.intersperse "," usedLetters ) ++ "] -> " ++
            getStmt
            ++ " return "
            ++ wrap (fullName ++ " " ++ concatMap (++"' ") (take (length fields) usedLetters))

---- contentheader put instance ----

writeContentHeaderPutInstForClass :: Class -> String
writeContentHeaderPutInstForClass (Class nam _ _ fields) =
    let fullName = "CH" ++ (fixClassName nam) in
    --binary instances
    (writeContentHeaderPutInstance fullName fields)

writeContentHeaderPutInstance :: String -> [Field] -> String
writeContentHeaderPutInstance fullName fields =
    "putContentHeaderProperties " ++ putDef ++ "\n"
    where
        manyLetters = map (:[]) ['a'..'z']
        usedLetters = take (length fields) manyLetters

        showBlob x =  " >> condPut " ++ x

        putStmt = concatMap showBlob usedLetters

        putDef =
            let wrap = if (length fields) /= 0 then ("("++) . (++")") else id
                pattern = fullName ++ concatMap (' ':) (take (length fields) manyLetters)
            in
                wrap pattern ++" = "
                ++ "putPropBits " ++ "[" ++ (concat $ L.intersperse "," $ map ("isJust " ++ ) usedLetters) ++ "] "
                ++ putStmt

---- contentheader class ids -----

writeContentHeaderClassIDsForClass :: Class -> String
writeContentHeaderClassIDsForClass (Class nam index _ fields) =
    let fullName = "CH" ++ (fixClassName nam) in
    --binary instances
    (writeContentHeaderClassIDsInstance fullName index fields)

writeContentHeaderClassIDsInstance :: String -> Int -> [Field] -> String
writeContentHeaderClassIDsInstance fullName classIndex fields =
    "getClassIDOf (" ++ fullName ++ (concat $replicate (length fields) " _") ++ ") = " ++ (show classIndex) ++ "\n"

readDomain :: Element -> (String, String)
readDomain d =
    let (Just domainName) = lookupAttr (unqual "name") $ elAttribs d
        (Just typ) = lookupAttr (unqual "type") $ elAttribs d
        in (domainName, typ)

readClass :: Element -> Class
readClass c =
    let (Just className) = lookupAttr (unqual "name") $ elAttribs c
        (Just classIndex) = lookupAttr (unqual "index") $ elAttribs c
        methods = map readMethod $ findChildren (unqual "method") c
        fields = map readField $ findChildren (unqual "field") c
    in Class className (read classIndex) methods fields

readMethod :: Element -> Method
readMethod m =
    let (Just methodName) = lookupAttr (unqual "name") $ elAttribs m
        (Just methodIndex) = lookupAttr (unqual "index") $ elAttribs m
        fields = map readField $ findChildren (unqual "field") m
    in Method methodName (read methodIndex) fields

readField :: Element -> Field
readField f =
    let (Just fieldName) = lookupAttr (unqual "name") $ elAttribs f
        fType = lookupAttr (unqual "type") $ elAttribs f
        fDomain = lookupAttr (unqual "domain") $ elAttribs f in
        case (fType, fDomain) of
            (Just t, _) -> TypeField fieldName t
            (_, Just d) -> DomainField fieldName d
            _           -> error ("Missing field type and domain attributes")
