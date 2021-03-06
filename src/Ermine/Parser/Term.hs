{-# LANGUAGE TupleSections #-}
{-# LANGUAGE PatternGuards #-}
--------------------------------------------------------------------
-- |
-- Copyright :  (c) Edward Kmett and Dan Doel 2013
-- License   :  BSD3
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable
--
-- This module provides the parser for terms
--------------------------------------------------------------------
module Ermine.Parser.Term
  ( anyType
  , term
  , terms
  , declarations
  , letBlock
  ) where

import Control.Lens hiding (op)
import Control.Applicative
import Control.Comonad
import Control.Monad.State hiding (guard)
import Data.Function
import Data.Either (partitionEithers)
import Data.List (groupBy, find)
import Data.Set as Set hiding (map)
import Data.Foldable (foldrM)
import Data.Text (Text, unpack)
import Data.Traversable hiding (mapM)
import Ermine.Builtin.Pattern
import Ermine.Builtin.Term
import Ermine.Parser.Style
import Ermine.Parser.Type as Type
import Ermine.Parser.Pattern
import Ermine.Syntax
import Ermine.Syntax.Literal
import Ermine.Syntax.Pattern
import Ermine.Syntax.Term
import Text.Parser.Combinators
import Text.Parser.Token

type Tm = Term Ann Text

-- | Parse an atomic term
term0 :: (Monad m, TokenParsing m) => m Tm
term0 = Var <$> termIdentifier
   <|> literal
   <|> parens (tup <$> terms)

term1 :: (Monad m, TokenParsing m) => m Tm
term1 = match
    <|> foldl1 App <$> some term0

sig :: (Monad m, TokenParsing m) => m Tm
sig = (maybe id (Sig ??) ??) <$> term1 <*> optional (colon *> annotation)

branch :: (Monad m, TokenParsing m) => m (Alt Ann (Term Ann) Text)
branch = do pp <- pattern
            reserve op "->"
            b <- term
            validate pp $ \n ->
                unexpected $ "duplicate bindings in pattern for: " ++ unpack n
            return $ alt pp b

match :: (Monad m, TokenParsing m) => m Tm
match = Case <$ symbol "case" <*> term <* symbol "of" <*> braces (semiSep branch)

term2 :: (Monad m, TokenParsing m) => m Tm
term2 = lambda <|> sig

patterns :: (Monad m, TokenParsing m) => m (Binder Text [Pattern Ann])
patterns = do pps <- sequenceA <$> some pattern
              validate pps $ \n ->
                  unexpected $ "duplicate bindings in pattern for: " ++ unpack n
              return pps

lambda :: (Monad m, TokenParsing m) => m Tm
lambda = lam <$> try (patterns <* reserve op "->") <*> term

literal :: (Monad m, TokenParsing m) => m Tm
literal = HardTerm . Lit <$>
  (either (Int . fromIntegral) Double <$> naturalOrDouble
    <|> String <$> stringLiteral
    <|> Char <$> charLiteral)

term :: (Monad m, TokenParsing m) => m Tm
term = letBlock <|> term2

letBlock :: (Monad m, TokenParsing m) => m Tm
letBlock = let_ <$ symbol "let" <*> braces declarations <* symbol "in" <*> term

terms :: (Monad m, TokenParsing m) => m [Tm]
terms = commaSep term

typeDecl :: (Monad m, TokenParsing m) => m TyDecl
typeDecl = (,) <$> try (termIdentifier <* colon) <*> annotation

termDeclClause :: (Monad m, TokenParsing m)
               => m (Text, PBody)
termDeclClause =
    (,) <$> termIdentifier
        <*> (PreBody <$> pattern0s <*> guarded <*> whereClause)
 where
 pattern0s = do ps <- sequenceA <$> many pattern0
                ps <$ validate ps
                        (\n -> unexpected $ "duplicate bindings in pattern for: " ++ unpack n)

guard :: (Monad m, TokenParsing m) => m (Tm, Tm)
guard = (,) <$ reserve op "|" <*> term <* reserve op "=" <*> term

guarded :: (Monad m, TokenParsing m) => m (Guarded Tm)
guarded = Guarded <$> some guard
      <|> Unguarded <$ reserve op "=" <*> term

type PBody = PreBody Ann Text
type Where = Binder Text [Binding Ann Text]

whereClause :: (Monad m, TokenParsing m) => m Where
whereClause = symbol "where" *> braces declarations <|> pure (pure [])

declClauses :: (Monad m, TokenParsing m) => m [Either TyDecl (Text, PBody)]
declClauses = semiSep $ (Left <$> typeDecl) <|> (Right <$> termDeclClause)

type TyDecl = (Text, Ann)
type TmDecl = (Text, [PBody])

decls :: (Monad m, TokenParsing m) => m ([TyDecl], [TmDecl])
decls = do (ts, cs) <- partitionEithers <$> declClauses
           fmap (ts,) . mapM validateShape $ groupBy ((==) `on` (^._1)) cs
 where
 validateShape l = let (name:_, pbs) = unzip l in
   if shapely pbs
     then return (name, pbs)
     else fail $ "Equations for `" ++ unpack name ++ "' have differing numbers of arguments."

validateDecls :: (Monad m, TokenParsing m) => [TyDecl] -> [TmDecl] -> m ()
validateDecls tys tms
  | Just n <- findDuplicate tyns =
    fail $ "Duplicate type declarations for `" ++ unpack n ++ "'."
  | Just n <- findDuplicate tmns =
    fail $ "Duplicate definitions for `" ++ unpack n ++ "'."
  | Just n <- uncovered tmns tyns =
    fail $ "No definition for declared value `" ++ unpack n ++ "'."
  | otherwise = return ()
 where
 tyns = map fst tys
 tmns = map fst tms

declarations :: (Monad m, TokenParsing m) => m (Binder Text [Binding Ann Text])
declarations = do
  (tys, tms) <- decls
  let -- TODO: Rendering
      bindType s
        | Just t <- lookup s tys = explicit t
        | otherwise              = implicit
  bindings (extend (uncurry bindType) <$> tms) <$ validateDecls tys tms

uncovered :: Ord a => [a] -> [a] -> Maybe a
uncovered xs ys = find (`Set.notMember` s) ys
 where
 s = Set.fromList xs

findDuplicate :: Ord a => [a] -> Maybe a
findDuplicate = flip evalState Set.empty . foldrM test Nothing
 where
 test e r = state $ \s -> if e `Set.member` s then (Just e, s) else (r, Set.insert e s)

