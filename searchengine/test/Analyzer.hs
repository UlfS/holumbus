{-# LANGUAGE OverloadedStrings #-}

module Main where
{-- Tests for Normalizers Analyzers Formatters #-}

import           Data.Text                              (Text)
import qualified Data.Text                              as T
import           Data.Time
--import           Data.Time.Format
import           System.Locale

import           Test.Framework
import           Test.Framework.Providers.HUnit
import           Test.Framework.Providers.QuickCheck2
import           Test.HUnit
import           Test.QuickCheck
--import qualified Test.QuickCheck.Monadic                as QM

import qualified Holumbus.Index.Schema                    as S
import qualified Holumbus.Index.Schema.Analyze            as A
import qualified Holumbus.Index.Schema.Normalize          as N
import qualified Holumbus.Index.Schema.Normalize.Date     as ND
import qualified Holumbus.Index.Schema.Normalize.Position as NP
import qualified Holumbus.Index.Schema.Normalize.Int      as NI

-- ----------------------------------------------------------------------------

main :: IO ()
main = defaultMain
       [
       -- Analyzer tests
         testCase "scanTextRE: text1 "             test_scan_text1
       , testCase "scanTextRE: date inv"           test_scan_date1
       , testCase "scanTextRE: date val"           test_scan_date2
       , testCase "scanTextRE: date val multiple"  test_scan_date3
       , testCase "scanTextRE: date val + inval"   test_scan_date4
       , testCase "scanTextRE: date val short   "  test_scan_date5
       , testCase "scanTextRE: date val shorter"   test_scan_date6

       -- Normalizer tests - validation
       , testProperty "typeValidator: text"        prop_validate_text
       , testProperty "typeValidator: int val"     prop_validate_int
       , testProperty "typeValidator: int inv"     prop_validate_int2
       , testProperty "typeValidator: date val"    prop_validate_date
       , testProperty "typeValidator: date inv"    prop_validate_date2

       -- Normalizer data - isAnyDate
       , testProperty "Normalizer:date YYYYMMDD"            prop_isAnyDate
       , testProperty "Normalizer:date 2013-01-01T21:12:12" prop_isAnyDate2
       , testProperty "Normalizer:date 2013"                prop_isAnyDate3

       -- Normalizer position
       , testProperty "Normlizer:pos double"       prop_isPosition_d
       , testProperty "Normlizer:pos text"         prop_isPosition_t
       , testCase     "Normlizer:norm pos int"     test_norm_pos
       , testCase     "Normlizer:norm pos dbl"     test_norm_pos4
       , testProperty "Normlizer:norm denorm dbl"  prop_norm_pos3

       -- Normalizer int
       , testProperty "Normlizer:isInt Int"        prop_isInt_int
       , testProperty "Normlizer:isInt Integer"    prop_isInt_integer
       , testProperty "Normlizer:isInt text"       prop_isInt_text
       , testProperty "Normlizer:isInt double"     prop_isInt_double
       , testCase     "Normlizer:isInt overflow"   test_isInt_overflow
       , testCase     "Normlizer:isInt nooverflow" test_isInt_overflow2
       , testCase     "Normlizer:isInt maxBound"   test_isInt_upper1
       , testCase     "Normlizer:isInt maxBound"   test_isInt_upper2
       , testCase     "Normlizer:isInt minBound"   test_isInt_lower1
       , testCase     "Normlizer:isInt minBound"   test_isInt_lower2

       , testProperty "Normlizer:normInt int"      prop_normInt_int
       , testProperty "Normlizer:normInt integer"  prop_normInt_integer
       , testCase     "Normlizer:isInt 1"          test_normInt1
       , testCase     "Normlizer:isInt -1"         test_normInt2
       , testCase     "Normlizer:isInt maxBound"   test_normInt3
       , testCase     "Normlizer:isInt minBound"   test_normInt4
       ]

-- ----------------------------------------------------------------------------
-- normalizer position tests

prop_isInt_int :: Gen Bool
prop_isInt_int = do
  val <- arbitrary :: Gen Int
  return . NI.isInt . T.pack . show $ val

prop_isInt_integer :: Gen Bool
prop_isInt_integer = do
  val <- arbitrary :: Gen Integer
  return . NI.isInt . T.pack .show $ val

prop_isInt_text :: Gen Bool
prop_isInt_text = do
  val <- niceText1
  return . not . NI.isInt $ val

prop_isInt_double :: Gen Bool
prop_isInt_double = do
  val <- arbitrary :: Gen Double
  return . not . NI.isInt . T.pack . show $ val

test_isInt_overflow :: Assertion
test_isInt_overflow = assertEqual "" False (NI.isInt  "10000000000000000000000000000000000000")

test_isInt_overflow2 :: Assertion
test_isInt_overflow2 = assertEqual "" True (NI.isInt  "6443264")

test_isInt_upper1 :: Assertion
test_isInt_upper1 = assertEqual "" True (NI.isInt  "9223372036854775807")

test_isInt_upper2 :: Assertion
test_isInt_upper2 = assertEqual "" False (NI.isInt  "9223372036854775808")

test_isInt_lower1 :: Assertion
test_isInt_lower1 = assertEqual "" True (NI.isInt  "-9223372036854775808")

test_isInt_lower2 :: Assertion
test_isInt_lower2 = assertEqual "" False (NI.isInt  "-9223372036854775809")

prop_normInt_int :: Gen Bool
prop_normInt_int = do
  val <- arbitrary :: Gen Int
  return $ 21 == T.length (NI.normalizeToText . T.pack . show $ val)

prop_normInt_integer :: Gen Bool
prop_normInt_integer = do
  val <- arbitrary :: Gen Integer
  return $ 21 == T.length (NI.normalizeToText . T.pack . show $ val)

test_normInt1 :: Assertion
test_normInt1 = assertEqual "" "100000000000000000001" (NI.normalizeToText "1")

test_normInt2 :: Assertion
test_normInt2 = assertEqual "" "000000000000000000001" (NI.normalizeToText "-1")

test_normInt3 :: Assertion
test_normInt3 = assertEqual "" "109223372036854775807" (NI.normalizeToText "9223372036854775807")

test_normInt4 :: Assertion
test_normInt4 = assertEqual "" "009223372036854775808" (NI.normalizeToText "-9223372036854775808")


-- ----------------------------------------------------------------------------
-- normalizer position tests

genPos :: Gen String
genPos = do
  lat  <- choose (-89,89)  :: Gen Int
  long <- choose (-179,179) :: Gen Int
  return $ concat [ show lat, ".000001-", show long, ".000002" ]

prop_isPosition_d :: Gen Bool
prop_isPosition_d = do
  pos  <- genPos
  return . NP.isPosition $ T.pack pos

prop_isPosition_t :: Gen Bool
prop_isPosition_t = do
  long <- niceText1
  lat  <- niceText1
  return $ False == NP.isPosition (T.concat [ long, "-", lat ])

test_norm_pos :: Assertion
test_norm_pos = assertEqual "" "110000111100000011000011001111001100000000000000" (NP.normalize "1-1")

test_norm_pos4 :: Assertion
test_norm_pos4 = assertEqual "" "110000111100000011000011001111001100000000000000" (NP.normalize "1.000000-1.000000")

prop_norm_pos3 :: Gen Bool
prop_norm_pos3 = do
  p <- genPos
  let pos = T.pack p 
  return $ pos == (NP.denormalize . NP.normalize $ pos)

-- ----------------------------------------------------------------------------
-- normalizer date tests

-- | test with date formatted like "2013-01-01"
-- | XXX everything fails?!?!
prop_isAnyDate :: Gen Bool
prop_isAnyDate = dateYYYYMMDD >>= return . ND.isAnyDate . T.unpack

prop_isAnyDate2 :: Gen Bool
prop_isAnyDate2 = return . ND.isAnyDate $ "2013-01-01T21:12:12"

prop_isAnyDate3 :: Gen Bool
prop_isAnyDate3 = return . ND.isAnyDate $ "2013"

-- | test date normalization
-- XXX
prop_norm_date :: Gen Bool
prop_norm_date = undefined

-- ----------------------------------------------------------------------------
-- normalizer tests - validation

-- | every random text should be a valid text
prop_validate_text :: Gen Bool
prop_validate_text = niceText1 >>= return . (N.typeValidator S.CText)

-- | every integer numbers should be valid numbers
prop_validate_int :: Gen Bool
prop_validate_int = do
  int <- arbitrary :: Gen Integer
  return $ N.typeValidator S.CInt (T.pack . show $ int)

-- | random text should not be considered a valid number
prop_validate_int2 :: Gen Bool
prop_validate_int2 = niceText1 >>= \t -> return $ False == N.typeValidator S.CInt ("a" `T.append` t)

-- | date formated "yyyy-mm-dd" should be valid
prop_validate_date :: Gen Bool
prop_validate_date = dateYYYYMMDD >>= return . (N.typeValidator S.CDate)

-- | random text should not be considered a valid date
prop_validate_date2 :: Gen Bool
prop_validate_date2 = niceText1 >>= \d -> return $ False == N.typeValidator S.CDate d

-- ----------------------------------------------------------------------------
-- scan tests

-- | test general text regex
test_scan_text1 :: Assertion
test_scan_text1 = assert $ length scan == 3
  where
  scan = A.scanTextRE "[^ \t\n\r]*" "w1 w2 w3"

-- | test date regex with invalid date given
test_scan_date1 :: Assertion
test_scan_date1 = assert $ length scan == 0
  where
  scan = A.scanTextRE "[0-9]{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))" "w1 w2 w3"

-- | test date regex with valid date given
test_scan_date2 :: Assertion
test_scan_date2 = assert $ length scan == 1
  where
  scan = A.scanTextRE "[0-9]{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))" "2013-01-01"

-- | test date regex with multiple dates given
test_scan_date3 :: Assertion
test_scan_date3 = assert $ length scan == 2
  where
  scan = A.scanTextRE "[0-9]{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))" "2013-01-01 2012-12-31"

-- | test date regex with date containing string
test_scan_date4 :: Assertion
test_scan_date4 = assert $ (length scan == 2) && (scan !! 1 == "2013-01-01")
  where
  scan = A.scanTextRE "[0-9]{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))" "2013-01-01 asd 2013-01-01"

-- | test date regex with invalid date given
test_scan_date5 :: Assertion
test_scan_date5 = assert $ length scan == 0
  where
  scan = A.scanTextRE "[0-9]{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))" "2013-01"

-- | test date regex with invalid date given
test_scan_date6 :: Assertion
test_scan_date6 = assert $ length scan == 0
  where
  scan = A.scanTextRE "[0-9]{4}-((0[1-9])|(1[0-2]))-((0[1-9])|([12][0-9])|(3[01]))" "2013"


-- ----------------------------------------------------------------------------
-- helper

niceText1 :: Gen Text
niceText1 = fmap T.pack . listOf1 . elements $ concat [" ", ['A'..'Z'], ['a'..'z']]

dateYYYYMMDD :: Gen Text
dateYYYYMMDD = arbitrary >>= \x -> return . T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" (newDate x)
  where
  newDate x = addDays (-x) (fromGregorian 2013 12 31)


