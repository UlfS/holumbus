module Holumbus.Index.ComprPrefixTreeIndex
( ComprOccPrefixTree(..)
)
where

import           Prelude                           as P

import           Holumbus.Index.Index
import qualified Holumbus.Index.Index              as Ix
import           Holumbus.Index.PrefixTreeIndex

import           Holumbus.Common.Occurrences       (Occurrences)
import           Holumbus.Common.DocIdMap          (DocIdMap)
import           Holumbus.Common.Compression       hiding (delete)

import           Control.Applicative               ((<$>))
import           Control.Arrow                     (second)

import qualified Holumbus.Data.PrefixTree          as PT



newtype ComprOccPrefixTree cv = ComprPT { comprPT :: DmPrefixTree cv}
    deriving Show

instance Index ComprOccPrefixTree where
    type IKey ComprOccPrefixTree v = PT.Key
    type IVal ComprOccPrefixTree v = Occurrences
    type ICon ComprOccPrefixTree v = (OccCompression (DocIdMap v))

    insert k v (ComprPT i)
        = ComprPT $ insert k (compressOcc v) i

    batchDelete ks (ComprPT i)
        = ComprPT $ batchDelete ks i

    empty
        = ComprPT $ empty

    fromList l
        = ComprPT . fromList $ P.map (second compressOcc) l

    toList (ComprPT i)
        = second decompressOcc <$> toList i

    search t k (ComprPT i)
        = second decompressOcc <$> search t k i

    unionWith op (ComprPT i1) (ComprPT i2)
        = ComprPT $ unionWith (\o1 o2 -> compressOcc $ op (decompressOcc o1) (decompressOcc o2)) i1 i2

    map f (ComprPT i)
        = ComprPT $ Ix.map (compressOcc . f . decompressOcc) i

    keys (ComprPT i)
        = keys i


