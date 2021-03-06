{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Cases
(
  -- * Processor
  process,
  -- ** Case Transformers
  CaseTransformer,
  lower,
  upper,
  title,
  -- ** Delimiters
  Delimiter,
  spinal,
  snake,
  camel,
  -- * Default Processors
  spinalize,
  snakify,
  camelize,
)
where

import           Control.Applicative 
import           Data.Maybe 
import           Data.Monoid 
import qualified Data.Attoparsec.Text as A
import qualified Data.Char as C
import qualified Data.Text as TS

-- * Part
-------------------------

-- | A parsed info and a text of a part.
data Part = 
  Word Case TS.Text |
  Digits TS.Text

data Case = Title | Upper | Lower

partToText :: Part -> TS.Text
partToText = \case
  Word _ t -> t
  Digits t -> t


-- * Parsers
-------------------------

upperParser :: A.Parser Part
upperParser = Word Upper <$> TS.pack <$> A.many1 char where
  char = do
    c <- A.satisfy C.isUpper
    ok <- maybe True (not . C.isLower) <$> A.peekChar
    if ok
      then return c
      else empty

lowerParser :: A.Parser Part
lowerParser = Word Lower <$> (A.takeWhile1 C.isLower)

titleParser :: A.Parser Part
titleParser = Word Title <$> (TS.cons <$> headChar <*> remainder) where
  headChar = A.satisfy C.isUpper
  remainder = A.takeWhile1 C.isLower

digitsParser :: A.Parser Part
digitsParser = Digits <$> (A.takeWhile1 C.isDigit)

partParser :: A.Parser Part
partParser = titleParser <|> upperParser <|> lowerParser <|> digitsParser

-- |
-- A parser, which does in-place processing, using the supplied 'Folder'.
partsParser :: Monoid r => Folder r -> A.Parser r
partsParser folder = loop mempty where
  loop r = 
    (partParser >>= loop . folder r) <|> 
    (A.anyChar *> loop r) <|>
    (A.endOfInput *> pure r)


-- * Folders
-------------------------

type Folder r = r -> Part -> r

type Delimiter = Folder (Maybe TS.Text)

spinal :: Delimiter
spinal = 
  (. partToText) . 
  fmap Just . 
  maybe id (\l r -> l <> "-" <> r)

snake :: Delimiter
snake = 
  (. partToText) . 
  fmap Just . 
  maybe id (\l r -> l <> "_" <> r)

camel :: Delimiter
camel = 
  fmap Just .
  maybe partToText (\l r -> l <> partToText (title r))


-- * CaseTransformers
-------------------------

type CaseTransformer = Part -> Part

lower :: CaseTransformer
lower = \case
  Word c t -> Word Lower t' where
    t' = case c of
      Title -> TS.uncons t |> \case
        Nothing -> t
        Just (h, t2) -> TS.cons (C.toLower h) t2
      Upper -> TS.toLower t
      Lower -> t
  p -> p

upper :: CaseTransformer
upper = \case
  Word c t -> Word Upper t' where
    t' = case c of
      Title -> TS.uncons t |> \case
        Nothing -> t
        Just (h, t2) -> TS.cons h (TS.toUpper t2)
      Upper -> t
      Lower -> TS.toUpper t
  p -> p

title :: CaseTransformer
title = \case
  Word c t -> Word Title t' where
    t' = case c of
      Title -> t
      Upper -> TS.uncons t |> \case
        Nothing -> t  
        Just (h, t2) -> TS.cons (C.toUpper h) (TS.toLower t2)
      Lower -> TS.uncons t |> \case
        Nothing -> t
        Just (h, t2) -> TS.cons (C.toUpper h) t2
  p -> p


-- * API
-------------------------

-- |
-- Extract separate words from an arbitrary text using a smart parser and
-- produce a new text using case transformation and delimiter functions.
-- 
-- Note: to skip case transformation use the 'id' function.
process :: CaseTransformer -> Delimiter -> TS.Text -> TS.Text
process tr fo = 
  fromMaybe "" .
  either (error . ("Cases parse failure: " <>)) id .
  A.parseOnly (partsParser $ (. tr) . fo)

-- |
-- Transform an arbitrary text into a lower spinal case.
-- 
-- Same as @('process' 'lower' 'spinal')@.
spinalize :: TS.Text -> TS.Text
spinalize = process lower spinal

-- |
-- Transform an arbitrary text into a lower snake case.
-- 
-- Same as @('process' 'lower' 'snake')@.
snakify :: TS.Text -> TS.Text
snakify = process lower snake

-- |
-- Transform an arbitrary text into a camel case, 
-- while preserving the case of the first character.
-- 
-- Same as @('process' 'id' 'camel')@.
camelize :: TS.Text -> TS.Text
camelize = process id camel

(|>) :: a -> (a -> b) -> b
a |> aToB = aToB a
{-# INLINE (|>) #-}

