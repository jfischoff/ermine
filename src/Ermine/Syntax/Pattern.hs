{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
--------------------------------------------------------------------
-- |
-- Copyright :  (c) Edward Kmett
-- License   :  BSD3
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable
--
--------------------------------------------------------------------
module Ermine.Syntax.Pattern
  ( Pattern(..)
  , Alt(..)
  , bitraverseAlt
  , getAlt, putAlt, getPat, putPat
  ) where

import Bound
import Control.Applicative
import Control.Monad
import Control.Lens
import Data.Bitraversable
import qualified Data.Binary as Binary
import Data.Binary (Binary)
import Data.Bytes.Serial
import Data.Bytes.Get
import Data.Bytes.Put
import Data.Foldable
import qualified Data.Serialize as Serialize
import Data.Serialize (Serialize)
import Ermine.Syntax
import Ermine.Syntax.Global
import Ermine.Syntax.Literal
import Ermine.Syntax.Scope

-- | Patterns used by 'Term'
data Pattern t
  = SigP t
  | WildcardP
  | AsP (Pattern t)
  | StrictP (Pattern t)
  | LazyP (Pattern t)
  | LitP Literal
  | ConP Global [Pattern t]
  | TupP [Pattern t]
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | One alternative of a core expression
data Alt t f a = Alt !(Pattern t) !(Scope Int f a)
  deriving (Eq,Show,Functor,Foldable,Traversable)

instance Bound (Alt t) where
  Alt p b >>>= f = Alt p (b >>>= f)

instance Monad f => BoundBy (Alt t f) f where
  boundBy f (Alt p b) = Alt p (boundBy f b)

-- | Helper function for traversing both sides of an 'Alt'.
bitraverseAlt :: (Bitraversable k, Applicative f) => (t -> f t') -> (a -> f b) -> Alt t (k t) a -> f (Alt t' (k t') b)
bitraverseAlt f g (Alt p b) = Alt <$> traverse f p <*> bitraverseScope f g b

instance (Bifunctor p, Choice p, Applicative f) => Tup p f (Pattern t) where
  tupled = prism TupP $ \p -> case p of TupP ps -> Right ps ; _ -> Left p

instance (Serial t, Serial1 f) => Serial1 (Alt t f)  where

-- | Binary serialization of a 'Alt', given serializers for its parameters.
putAlt :: MonadPut m => (t -> m p) -> (a -> m p) -> Alt t f a -> m ()
putAlt pt pa (Alt p s) = serializeWith pt p >> serializeWith pa s

getAlt :: MonadGet m => m t -> m a -> m (Alt t f a)
getAlt gt ga = liftM2 Alt (deserializeWith gt) (deserializeWith ga)

instance Serial1 Pattern where
  serializeWith pt (SigP t)    = putWord8 0 >> pt t
  serializeWith _  WildcardP   = putWord8 1
  serializeWith pt (AsP p)     = putWord8 2 >> serializeWith pt p
  serializeWith pt (StrictP p) = putWord8 3 >> serializeWith pt p
  serializeWith pt (LazyP p)   = putWord8 4 >> serializeWith pt p
  serializeWith _  (LitP l)    = putWord8 5 >> serialize l
  serializeWith pt (ConP g ps) = putWord8 6 >> serialize g >> serializeWith (serializeWith pt) ps
  serializeWith pt (TupP ps)   = putWord8 7 >> serializeWith (serializeWith pt) ps

  deserializeWith gt = getWord8 >>= \b -> case b of
    0 -> liftM SigP gt
    1 -> return WildcardP
    2 -> liftM AsP $ deserializeWith gt
    3 -> liftM StrictP $ deserializeWith gt
    4 -> liftM LazyP $ deserializeWith gt
    5 -> liftM LitP deserialize
    6 -> liftM2 ConP deserialize $ deserializeWith (deserializeWith gt)
    7 -> liftM TupP $ deserializeWith (deserializeWith gt)
    _ -> fail $ "get Pattern: unexpected constructor tag: " ++ show b

instance Binary t => Binary (Pattern t) where
  put = serializeWith Binary.put
  get = deserializeWith Binary.get
