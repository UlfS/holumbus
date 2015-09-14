{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeFamilies               #-}

-- ----------------------------------------------------------------------------
{- |
  Text index using the 'DocIdMap' based on the 'StringMap' implementation.
-}
-- ----------------------------------------------------------------------------

module Hunt.Index.PrefixTreeIndex
    ( DmPrefixTree (..)
    , SimplePrefixTreeIndex (..)
    , PrefixTreeIndexInt (..)
    , PrefixTreeIndexDate (..)
    )
where

import           Prelude hiding (Word)

import           Control.DeepSeq

import           Data.Bijection
import           Data.Bijection.Instances ()
import           Data.Binary              (Binary (..))
import qualified Data.List                as L
import qualified Data.StringMap.Strict    as SM
import           Data.Text                (Text)
import           Data.Typeable


import           Hunt.Common.BasicTypes
import           Hunt.Common.DocIdSet     (DocIdSet)
import           Hunt.Index
import qualified Hunt.Index               as Ix
import           Hunt.Index.Proxy.KeyIndex
import           Hunt.Scoring.Keys        (similar, similarInt, similarRangeInt)
import           Hunt.Utility

import qualified Hunt.Index.Schema.Normalize.Date     as Date
import qualified Hunt.Index.Schema.Normalize.Int      as Int

-- import           Debug.Trace

-- ------------------------------------------------------------

-- | Text index using 'DocIdMap' based on the 'StringMap' implementation.
--   Note that the value parameter is on the type of the 'DocIdMap' value and not the 'DocIdSet'
--   itself.

newtype DmPrefixTree v
  = DmPT { dmPT :: SM.StringMap v}
  deriving (Eq, Show, NFData, Typeable)

mkDmPT :: NFData v => SM.StringMap v -> DmPrefixTree v
mkDmPT v = DmPT $! v

-- ------------------------------------------------------------

instance IndexValue v => Binary (DmPrefixTree v) where
  put = put . dmPT
  get = get >>= return . mkDmPT

-- ------------------------------------------------------------

instance (IndexValue v) => Index (DmPrefixTree v)  where
  type IKey (DmPrefixTree v) = SM.Key
  type IVal (DmPrefixTree v) = v

  insertList kvs (DmPT pt) =
    mkDmPT $ L.foldl' (\ m' (k', v') -> SM.insertWith mappend k' (fromOccurrences v') m') pt kvs

    {- this is a nice try, but does not do what it should do,
       at least not for [("a", occ1), ("a", occ2)]

       mkDmPT $ SM.unionWith op pt (SM.fromList kvs)
    -}

  deleteDocs ks (DmPT pt)
    = mkDmPT $ SM.mapMaybe (diffValues ks) pt

  empty
    = mkDmPT $ SM.empty

  fromList
    = mkDmPT . SM.fromList . fromOccurrenceList

  toList (DmPT pt)
    = toSearchResults . SM.toList $ pt

  search t k (DmPT pt)
    = toSearchResults $ case t of
        Case         -> case SM.lookup k pt of
                          Nothing -> []
                          Just xs -> [(k,xs)]
        NoCase       -> luCase k pt
        PrefixCase   -> pfCase k pt
        PrefixNoCase -> pfNoCase k pt
    where
    toL      = SM.toListShortestFirst
    luCase   = toL .:: SM.lookupNoCase
    pfCase   = toL .:: SM.prefixFilter
    pfNoCase = toL .:: SM.prefixFilterNoCase

  lookupRange k1 k2 (DmPT pt)
    = toSearchResults . SM.toList $ SM.lookupRange k1 k2 pt

  unionWith op (DmPT pt1) (DmPT pt2)
    = mkDmPT $ SM.unionWith op pt1 pt2

{-
  unionWithConv to f (DmPT i1) (DmPT i2)
    = liftM mkDmPT $ unionWithConv to f i1 i2
-}

  map f (DmPT pt)
    = mkDmPT $ SM.map f pt

  mapMaybe f (DmPT pt)
    = mkDmPT $ SM.mapMaybe f pt

  keys (DmPT pt)
    = SM.keys pt

-- ------------------------------------------------------------
-- Simple minimal PrefixTreeIndex based on the 'StringMap'
-- ------------------------------------------------------------

-- | Integer index using a 'StringMap'-implementation.
newtype SimplePrefixTreeIndex
  = SimplePTIx { simplePTIx :: KeyProxyIndex Text (DmPrefixTree DocIdSet) }
  deriving (Eq, Show, NFData, Typeable)

mkSimplePTIx :: KeyProxyIndex Text (DmPrefixTree DocIdSet)
                -> SimplePrefixTreeIndex
mkSimplePTIx x = SimplePTIx $! x

-- ------------------------------------------------------------

instance Binary SimplePrefixTreeIndex where
  put = put . simplePTIx
  get = get >>= return . mkSimplePTIx

-- ------------------------------------------------------------

instance Index SimplePrefixTreeIndex where
  type IKey SimplePrefixTreeIndex = Text
  type IVal SimplePrefixTreeIndex = DocIdSet

  insertList wos (SimplePTIx i)
    = mkSimplePTIx $ insertList wos i

  deleteDocs docIds (SimplePTIx i)
    = mkSimplePTIx $ deleteDocs docIds i

  empty
    = mkSimplePTIx $ empty

  fromList l
    = mkSimplePTIx $ fromList l

  toList (SimplePTIx i)
    = toList i

  search t k (SimplePTIx i)
    = search t k i

  searchSc t k m
      = L.map scoreWord $ search t k m
        where
          scoreWord (w, r)
              = (w, (similar k w, r)) -- not similarInt, it's a word index, not an int index

  lookupRange k1 k2 (SimplePTIx i)
    = lookupRange k1 k2 i

  {- it's a word index, similar should be the same as in InvertedIndex, not as in an int index
  lookupRangeSc k1 k2 m
    = L.map scoreWord $ lookupRange k1 k2 m
      where
        scoreWord (w, r)
            = (w, (similarRangeInt k1 k2 w, r))
  -- -}

  unionWith op (SimplePTIx i1) (SimplePTIx i2)
    = mkSimplePTIx $ unionWith op i1 i2

--  unionWithConv to' f (SimplePTIx i1) (SimplePTIx i2)
--    = mkSimplePTIx $ unionWithConv to' f i1 i2

  map f (SimplePTIx i)
    = mkSimplePTIx $ Ix.map f i

  mapMaybe f (SimplePTIx i)
    = mkSimplePTIx $ Ix.mapMaybe f i

  keys (SimplePTIx i)
    = keys i


-- ------------------------------------------------------------
-- PrefixTree index using int proxy for numeric data
-- ------------------------------------------------------------

-- | Newtype to allow integer normalization 'Bijection' instance.
newtype UnInt = UnInt { unInt :: Text }
  deriving (Show, Eq, NFData)

instance Bijection UnInt Text where
  to   = Int.denormalizeFromText . unInt
  from = UnInt . Int.normalizeToText

instance Bijection Text UnInt where
  to   = UnInt
  from = unInt

-- ------------------------------------------------------------

-- | Integer index using a 'StringMap'-implementation.
newtype PrefixTreeIndexInt
  = InvIntIx { invIntIx :: KeyProxyIndex Text
                           (KeyProxyIndex UnInt
                            (KeyProxyIndex Text
                             (DmPrefixTree DocIdSet)))
             }
  deriving (Eq, Show, NFData, Typeable)

mkInvIntIx :: KeyProxyIndex Text (KeyProxyIndex UnInt (KeyProxyIndex Text (DmPrefixTree DocIdSet)))
              -> PrefixTreeIndexInt
mkInvIntIx x = InvIntIx $! x

-- ------------------------------------------------------------

instance Binary PrefixTreeIndexInt where
  put = put . invIntIx
  get = get >>= return . InvIntIx

-- ------------------------------------------------------------

instance Index PrefixTreeIndexInt where
  type IKey PrefixTreeIndexInt = Text
  type IVal PrefixTreeIndexInt = DocIdSet

  insertList wos (InvIntIx i)
    = mkInvIntIx $ insertList wos i

  deleteDocs docIds (InvIntIx i)
    = mkInvIntIx $ deleteDocs docIds i

  empty
    = mkInvIntIx $ empty

  fromList l
    = mkInvIntIx $ fromList l

  toList (InvIntIx i)
    = toList i

  search t k (InvIntIx i)
    = search t k i

  searchSc t k m
      = L.map scoreWord $ search t k m
        where
          scoreWord (w, r)
              = (w, (similarInt k w, r))

  lookupRange k1 k2 (InvIntIx i)
    = lookupRange k1 k2 i

  lookupRangeSc k1 k2 m
    = L.map scoreWord $ lookupRange k1 k2 m
      where
        scoreWord (w, r)
            = (w, (similarRangeInt k1 k2 w, r))

  unionWith op (InvIntIx i1) (InvIntIx i2)
    = mkInvIntIx $ unionWith op i1 i2

--  unionWithConv to' f (InvIntIx i1) (InvIntIx i2)
--    = mkInvIntIx $ unionWithConv to' f i1 i2

  map f (InvIntIx i)
    = mkInvIntIx $ Ix.map f i

  mapMaybe f (InvIntIx i)
    = mkInvIntIx $ Ix.mapMaybe f i

  keys (InvIntIx i)
    = keys i

-- ------------------------------------------------------------
-- inverted index using date proxy for dates
-- ------------------------------------------------------------

-- | Newtype to allow date normalization 'Bijection' instance.
newtype UnDate = UnDate { unDate :: Text }
  deriving (Show, Eq, NFData)

instance Bijection UnDate Text where
  to   = Date.denormalize . unDate
  from = UnDate . Date.normalize

instance Bijection Text UnDate where
  to   = UnDate
  from = unDate

-- ------------------------------------------------------------

-- | Date index using a 'StringMap'-implementation.
newtype PrefixTreeIndexDate
  = InvDateIx { invDateIx :: KeyProxyIndex Text
                             (KeyProxyIndex UnDate
                              (KeyProxyIndex Text
                               (DmPrefixTree DocIdSet)))
              }
  deriving (Eq, Show, NFData, Typeable)

mkInvDateIx :: KeyProxyIndex Text (KeyProxyIndex UnDate (KeyProxyIndex Text (DmPrefixTree DocIdSet)))
               -> PrefixTreeIndexDate
mkInvDateIx x = InvDateIx $! x

-- ------------------------------------------------------------

instance Binary PrefixTreeIndexDate where
  put = put . invDateIx
  get = get >>= return . mkInvDateIx

-- ------------------------------------------------------------

instance Index PrefixTreeIndexDate where
  type IKey PrefixTreeIndexDate = Word
  type IVal PrefixTreeIndexDate = DocIdSet

  insertList wos (InvDateIx i)
    = mkInvDateIx $ insertList wos i

  deleteDocs docIds (InvDateIx i)
    = mkInvDateIx $ deleteDocs docIds i

  empty
    = mkInvDateIx $ empty

  fromList l
    = mkInvDateIx $ fromList l

  toList (InvDateIx i)
    = toList i

  search t k (InvDateIx i)
    = search t k i

  -- TODO: searchSc and lookupRangeSc implementation similar to PrefixTreeIndexInt and InvertedIndex

  lookupRange k1 k2 (InvDateIx i)
    = lookupRange k1 k2 i

  unionWith op (InvDateIx i1) (InvDateIx i2)
    = mkInvDateIx $ unionWith op i1 i2

--  unionWithConv to' f (InvDateIx i1) (InvDateIx i2)
--    = mkInvDateIx $ unionWithConv to' f i1 i2

  map f (InvDateIx i)
    = mkInvDateIx $ Ix.map f i

  mapMaybe f (InvDateIx i)
    = mkInvDateIx $ Ix.mapMaybe f i

  keys (InvDateIx i)
    = Ix.keys i

-- ------------------------------------------------------------
