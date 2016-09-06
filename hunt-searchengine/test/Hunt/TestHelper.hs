{-# LANGUAGE CPP                       #-}
{-# LANGUAGE ConstraintKinds           #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeSynonymInstances      #-}
{-# OPTIONS -fno-warn-orphans          #-}

-- ----------------------------------------------------------------------------
{- |
  Helper and generator for test suites.
-}
-- ----------------------------------------------------------------------------

module Hunt.TestHelper where

import           Control.Monad                (foldM)
import           System.Random
import           Test.QuickCheck
import           Test.QuickCheck.Gen
import           Test.QuickCheck.Monadic
import           Test.QuickCheck.Random

import qualified Control.Monad.Parallel       as Par
import           Data.Default
import           Data.Map                     (Map)
import qualified Data.Map                     as M
import           Data.Text                    (Text)
import qualified Data.Text                    as T

-- import           Hunt.Common
import qualified Hunt.Common.DocDesc          as DD
import qualified Hunt.Common.DocIdSet         as DS
import qualified Hunt.Common.Occurrences      as Occ
import qualified Hunt.Common.Positions        as Pos

import           Hunt.ClientInterface         hiding (mkDescription)
import           Hunt.Interpreter.Command

import           Hunt.Common.BasicTypes
import           Hunt.Common.DocId
import           Hunt.Common.Document         (Document (..))
import qualified Hunt.ContextIndex            as ConIx
import qualified Hunt.DocTable                as Dt
import qualified Hunt.DocTable.HashedDocTable as HDt
import qualified Hunt.Index                   as Ix
import           Hunt.Index.IndexImpl
import qualified Hunt.Index.InvertedIndex     as InvIx
import           Hunt.Index.Schema
import           Hunt.Scoring.Score
import           Hunt.Utility

import           Data.Time
#if !MIN_VERSION_time(1, 5, 0)
import           System.Locale
#endif

instance Par.MonadParallel (PropertyM IO) where

insertCx :: Context -> ConIx.ContextIndex
insertCx cx
     = ConIx.insertContext cx (mkIndex ix) def ConIx.empty
     where
       ix :: InvIx.InvertedIndex
       ix = Ix.empty


mkInsertList' :: Gen [(Document, Words)]
mkInsertList' = mkDocuments >>= mkInsertList

mkInsertList :: [Document] -> Gen [(Document, Words)]
mkInsertList docs = mapM (\doc -> mkWords >>= \wrds -> return (doc, wrds)) docs

-- --------------------
-- Arbitrary Words

-- using context1 .. context5 as fixed contexts
-- arbitrary context names would not work well in tests
mkWords :: Gen Words
mkWords = mapM addWordsToCx cxs >>= return . M.fromList
  where
  addWordsToCx cx = mkWordList >>= \l -> return (cx,l)
  cxs = map (\i -> T.pack $ "context" ++ (show i)) ([1..5] :: [Int])

mkWordList :: Gen WordList
mkWordList = listOf pair >>= return . M.fromList
  where
  pair = do
    word <- niceText1
    pos  <- listOf arbitrary :: Gen [Int]
    return (word, pos)

instance Arbitrary (HDt.Documents Document) where
  arbitrary = mkDocTable'

mkDocTables :: Gen [(HDt.Documents Document)]
mkDocTables = do
  -- generate list of distinct documents so
  -- that generated doctables are disjunct.
  -- Thats important for some testcases
  docs <- mkDocuments
  mapM mkDocTable $ partitionListByLength 10 docs

mkDocTable' :: Gen (HDt.Documents Document)
mkDocTable' = do
  docs <- mkDocuments
  mkDocTable docs

mkDocTable :: [Document] -> Gen (HDt.Documents Document)
mkDocTable docs = foldM (\dt doc -> Dt.insert doc dt >>= return . snd) Dt.empty docs

instance Arbitrary [Document] where
   arbitrary = mkDocuments

mkDocuments :: Gen [Document]
mkDocuments = do
  numberOfDocuments <- arbitrary :: Gen Int
  mapM mkDocument [1..numberOfDocuments]

instance Arbitrary Document where
   arbitrary = mkDocument'

mkDocument' :: Gen Document
mkDocument' = arbitrary >>= mkDocument

mkDocument :: Int -> Gen Document
mkDocument uri' = do
  d <- mkDescription
  w <- arbitrary
  return $ Document (T.pack . show $ uri') d (SC w)

mkDescription :: Gen Description
mkDescription = do
  txt <- niceText1
  txt2 <- niceText1
  return $ DD.fromList [ ("key1", txt)
                       , ("key2", txt2)
                       ]
-- --------------------
-- Arbitrary Occurrences

instance Arbitrary Occ.Occurrences where
  arbitrary = mkOccurrences

mkOccurrences :: Gen Occ.Occurrences
mkOccurrences = listOf mkPositions >>= foldM foldOccs Occ.empty
  where
  foldOccs occs ps = do
    docId <- arbitrary :: Gen Int
    return $ Occ.insert' (mkDocId docId) ps occs

mkPositions :: Gen Pos.Positions
mkPositions = listOf arbitrary >>= return . Pos.fromList

instance Arbitrary DS.DocIdSet where
  arbitrary = mkDocIdSet

instance Arbitrary DocId where
  arbitrary = arbitrary >>= \i -> return . mkDocId $ (i :: Int)

mkDocIdSet :: Gen DS.DocIdSet
mkDocIdSet = listOf arbitrary >>= return . DS.fromList


-- --------------------
-- Arbitrary ApiDocument

apiDocs :: Int -> Int -> IO [ApiDocument]
apiDocs = mkData apiDocGen


mkData :: (Int -> Gen a) -> Int -> Int -> IO [a]
mkData gen minS maxS =
  do rnd0 <- newQCGen --newStdGen
     let rnds rnd = rnd1 : rnds rnd2 where (rnd1,rnd2) = System.Random.split rnd
     return [unGen (gen i) r n | ((r,n),i) <- rnds rnd0 `zip` cycle [minS..maxS] `zip` [1..]] -- simple cycle


apiDocGen :: Int -> Gen ApiDocument
apiDocGen n = do
  desc_    <- descriptionGen
  let ix  =  mkIndexData n desc_
  return  $ ApiDocument uri_ ix desc_  1.0
  where uri_ = T.pack . ("rnd://" ++) . show $ n

niceText1 :: Gen Text
niceText1 = fmap T.pack . listOf1 . elements $ concat [" ", ['A'..'Z'], ['a'..'z']]


descriptionGen :: Gen Description
descriptionGen = do
  tuples <- listOf kvTuples
  return $ DD.fromList tuples
  where
  kvTuples = do
    a <- resize 15 niceText1 -- keys are short
    b <- niceText1
    return (a,b)


mkIndexData :: Int -> Description -> Map Context Content
mkIndexData i d = M.fromList
                $ map (\c -> ("context" `T.append` (T.pack $ show c), prefixx c)) [0..i]
  where
--  index   = T.pack $ show i
  prefixx n = T.intercalate " " . map (T.take n . T.filter (/=' ')) $ values
  values = map (T.pack . show . snd) $ DD.toList d

-- --------------------------------------
-- Other

dateYYYYMMDD :: Gen Text
dateYYYYMMDD = arbitrary >>= \x -> return . T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" (newDate x)
  where
  newDate x = addDays (-x) (fromGregorian 2013 12 31)

-- ------------------------------------------------------------
-- Example documents and contexts

-- | test document with "brain" document description
--   and term "brain" added to index
brainDoc' :: URI -> ApiDocument
brainDoc' uri'
    = addBrainDescAndIx
      $ mkApiDoc uri'

brainDoc :: ApiDocument
brainDoc
    = brainDoc' "test://0"


addBrainDescAndIx :: ApiDocument -> ApiDocument
addBrainDescAndIx
    = setDescription descr
      . setIndex (M.fromList [("default", td)])
    where
      td = "Brain"
      descr = DD.fromList [ ("name", "Brain" :: String)
                          , ("mission", "take over the world")
                          , ("legs", "4")
                          ]

-- | test document with "brain" description and also a value
--   added to the datecontext
dateDoc' :: URI -> ApiDocument
dateDoc' uri'
    = addToIndex "datecontext" "2013-01-01"
      $ addBrainDescAndIx
      $ mkApiDoc uri'

dateDoc :: ApiDocument
dateDoc
    = dateDoc' "test://1"

-- | test document with "brain" description and also a value
--   added to the geocontext
geoDoc'' :: URI -> Text -> ApiDocument
geoDoc'' uri' position
    = addToIndex "geocontext" position
      $ addBrainDescAndIx
      $ mkApiDoc uri'

geoDoc' :: Text -> ApiDocument
geoDoc' pos
    = geoDoc'' "test://2" pos

geoDoc :: ApiDocument
geoDoc = geoDoc' "53.60000-10.00000"

-- example apidoc
brainDocUpdate :: ApiDocument
brainDocUpdate = setDescription descr $ brainDoc
  where
  descr = DD.fromList [("name", "Pinky" :: String), ("mission", "ask stupid questions")]

brainDocMerged :: ApiDocument
brainDocMerged
    = changeDescription (`DD.union` (getDescription brainDoc))
      $ brainDocUpdate

-- | insert default text context command
insertDefaultContext :: Command
insertDefaultContext = uncurry cmdInsertContext defaultContextInfo

-- | insert geo context command
insertGeoContext :: Command
insertGeoContext = uncurry cmdInsertContext geoContextInfo

-- | insert date context command
insertDateContext :: Command
insertDateContext = uncurry cmdInsertContext dateContextInfo

-- | default text context
defaultContextInfo :: (Context, ContextSchema)
defaultContextInfo = ("default", ContextSchema Nothing [] 1 True ctText)

-- | default date context
dateContextInfo :: (Context, ContextSchema)
dateContextInfo = ("datecontext", ContextSchema Nothing [] 1 True ctDate)

-- | default geo context
geoContextInfo :: (Context, ContextSchema)
geoContextInfo = ("geocontext", ContextSchema Nothing [] 1 True ctPosition)
