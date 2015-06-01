{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ImpredicativeTypes #-}
module Hunt.ContextIndex.Insert where

import           Hunt.Common.BasicTypes
import           Hunt.Common.DocDesc as DocDesc
import           Hunt.Common.DocId
import qualified Hunt.Common.DocIdSet as DocIdSet
import           Hunt.Common.Document as Doc
import           Hunt.Common.Occurrences (Occurrences)
import qualified Hunt.Common.Occurrences as Occ
import           Hunt.ContextIndex.Delete (delete')
import           Hunt.ContextIndex.Documents
import           Hunt.ContextIndex.Types
import           Hunt.DocTable (DocTable)
import qualified Hunt.DocTable as Dt
import qualified Hunt.Index as Ix
import qualified Hunt.Index.IndexImpl as Ix
import           Hunt.Scoring.Score
import           Hunt.Utility

import           Control.Applicative
import           Control.Arrow
import           Control.Monad
import qualified Control.Monad.Parallel as Par
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Monoid

{-
-- | Insert a Document and Words.
--
--   /Note/: For multiple inserts, use the more efficient 'insertList'.
insert :: (Par.MonadParallel m, Applicative m, DocTable dt)
       => Dt.DValue dt -> Words -> ContextIndex dt -> m (ContextIndex dt)
insert doc wrds ix = insertList [(doc,wrds)] ix
-}

--   This is more efficient than using fold and with 'insert'.
-- | Insert multiple documents and words.
insertList :: (Par.MonadParallel m, Applicative m, DocTable dt) =>
              [(Dt.DValue dt, Words)] ->
              ContextIndex dt -> m (ContextIndex dt)
insertList docAndWords ixx
    = do -- insert to doctable and generate docId
         tablesAndWords <- Par.mapM createDocTableFromPartition
                           $ partitionListByLength 20 docAndWords

         -- union doctables and docid-words pairs
         (newDt, docIdsAndWords) <- unionDocTables tablesAndWords Dt.empty

         -- insert words to index
         newIx  <- batchAddWordsM docIdsAndWords (newContextMap (ciSchema ixx))
         newSeg <- newSegment (nextSegmentId ixx) newIx newDt

         return $! ixx { ciSegments = newSeg : ciSegments ixx }

-- takes list of documents with wordlist. creates new 'DocTable' and
-- inserts each document of the list into it.
createDocTableFromPartition :: (Par.MonadParallel m, DocTable dt) =>
                               [(Dt.DValue dt, Words)] -> m (dt, [(DocId, Words)])
createDocTableFromPartition ds
    = foldM toDocTable (Dt.empty, []) ds
    where
      toDocTable (dt, resIdsAndWords) (doc, ws)
        = do (dId, dt') <- Dt.insert doc dt
             return (dt', (dId, ws):resIdsAndWords)

-- takes list of doctables with lists of docid-words pairs attached
-- unions the doctables to one big doctable and concats the docid-words
-- pairs to one list
unionDocTables :: (DocTable dt, Par.MonadParallel m) =>
                  [(dt, [(DocId, Words)])] -> dt -> m (dt, [(DocId, Words)])
unionDocTables tablesAndWords oldDt
    = do step <- Par.mapM unionDtsAndWords $ mkPairs tablesAndWords
         case step of
          []      -> return (Dt.empty, [])
          [(d,w)] -> do n <- Dt.union oldDt d
                        return (n, w)
          xs      -> unionDocTables xs oldDt
    where
      unionDtsAndWords ((dt1, ws1), (dt2, ws2))
        = do dt <- Dt.union dt1 dt2
             return (dt, ws1 ++ ws2)

      mkPairs []       = []
      mkPairs (a:[])   = [(a,(Dt.empty,[]))]
      mkPairs (a:b:xs) = (a,b):mkPairs xs

-- | Adds words associated to a document to the index.
--

-- | Add words for a document to the 'Index'.
--
--   /Note/: Adds words to /existing/ 'Context's.
batchAddWordsM :: (Functor m, Par.MonadParallel m) =>
                  [(DocId, Words)] -> ContextMap -> m ContextMap
batchAddWordsM [] ix
    = return ix

batchAddWordsM vs (ContextMap m)
    = ContextMap <$> mapWithKeyMP foldinsertList m
    where
      foldinsertList :: (Functor m, Monad m) =>
                        Context -> Ix.IndexImpl -> m Ix.IndexImpl
      foldinsertList cx (Ix.IndexImpl impl)
          = Ix.mkIndex <$>
            Ix.insertListM (contentForCx cx vs) impl

-- | Computes the words and occurrences out of a list for one context

contentForCx :: Context -> [(DocId, Words)] -> [(Word, Occurrences)]
contentForCx cx vs
    = concatMap (invert . second (getWlForCx cx)) $ vs
          where
            invert (did, wl)
                = map (second (Occ.singleton' did)) $ Map.toList wl
            getWlForCx cx' ws'
              = Map.findWithDefault Map.empty cx' ws'

mapWithKeyMP :: (Par.MonadParallel m, Ord k) => (k -> a -> m b) -> Map k a -> m (Map k b)
mapWithKeyMP f m =
  (Par.mapM (\(k, a) ->
              do b <- f k a
                 return (k, b)
            ) $ Map.toAscList m) >>=
    return . Map.fromAscList

nextSegmentId :: ContextIndex dt -> SegmentId
nextSegmentId ixx
  = case ciSegments ixx of
     []    -> SegmentId 1
     (x:_) -> succ (segId x)

newSegment :: Monad m => SegmentId -> ContextMap -> dt -> m (Segment dt)
newSegment sid ix docs
  = return $! Segment { segId          = sid
                      , segIndex       = ix
                      , segDocs        = docs
                      , segState       = SegUncommited
                      , segDeletedCxs  = mempty
                      , segDeletedDocs = mempty
                      }

-- | Modify the description of a document and add words
--   (occurrences for that document) to the index.
modifyWithDescription :: (Par.MonadParallel m, Applicative m, DocTable dt) =>
                         Score -> Description -> Words -> DocId -> ContextIndex dt ->
                         m (ContextIndex dt)
modifyWithDescription weight descr wrds dId ixx
  = do Just doc      <- lookupDocument ixx dId
       ixx'          <- delete' (DocIdSet.singleton dId) ixx
       (dId', newDt) <- Dt.insert (mergeDescr doc) Dt.empty

       newIx         <- batchAddWordsM [(dId', wrds)] (newContextMap (ciSchema ixx))
       newSeg        <- newSegment (nextSegmentId ixx') newIx newDt
       return $! ixx { ciSegments = newSeg : ciSegments ixx }

  where
      -- M.union is left-biased
      -- flip to use new values for existing keys
      -- no flip to keep old values
      --
      -- Null values in new descr will remove associated attributes
    mergeDescr
      = wrap . Doc.update (updateWeight . updateDescr) . unwrap
      where
        updateWeight d
          | weight == noScore = d
          | otherwise         = d {wght = weight}

        updateDescr d           = -- trc "updateDescr res=" $
          d {desc = DocDesc.deleteNull $
                    flip DocDesc.union d' descr'
            }
          where
            d'     = -- trc "updateDescr old=" $
              desc d
            descr' = -- trc "updateDescr new=" $
              descr
