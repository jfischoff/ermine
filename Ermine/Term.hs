{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
--------------------------------------------------------------------
-- |
-- Module    :  Ermine.Term
-- Copyright :  (c) Edward Kmett and Dan Doel 2012
-- License   :  BSD3
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable (DeriveDataTypeable)
--------------------------------------------------------------------
module Ermine.Term
  ( HardTerm(..)
  , Term
  ) where

import Bound
import Control.Lens
import Control.Applicative
import Control.Monad (ap)
import Data.Bifoldable
import Data.Bifunctor
import Data.Bitraversable
import Data.Foldable
import Data.IntMap hiding (map)
import Data.Map hiding (map)
import Data.Set hiding (map)
import Data.Void
import Ermine.Global
import Ermine.Kind hiding (Var)
import qualified Ermine.Kind as Kind
import Ermine.Prim
import Ermine.Scope
import Ermine.Trifunctor
import Ermine.Type hiding (Var)
import qualified Ermine.Type as Type
import Prelude.Extras

data Pat t
  = VarP
  | SigP t
  | WildcardP
  | StrictP (Pat t)
  | LazyP (Pat t)
  | PrimP Prim [Pat t]

data HardTerm
  = Prim Prim
  | Hole
  deriving (Eq, Ord, Show)

data Term t a
  = Var a
  | !(Term t a) :$ !(Term t a)
  | HardTerm HardTerm
  | Sig (Term t a) t
  | Lam (Pat t) !(Scope Int (Term t) a)
  | Case (Term t a) [Alt t a]
  -- | Let [Scope Int (Term t) a] (Scope Int (Term t) a)
  | Loc Rendering (Term t a)
  | Remember !Int (Term t a)
  deriving (Show, Functor, Foldable, Traversable)

data Alt t a = Alt !(Pat t) !(Scope Int (Term t) a)
  deriving (Show, Functor, Foldable, Traversable)

instance Bifunctor Alt where
  bimap = bimapDefault

instance Bifoldable Alt where
  bifoldMap = bifoldMapDefault

instance Bitraversable Alt where
  bitraverse f g (Alt p b) = Alt <$> traverse f p <*> bitraverseScope f g b

instance (Eq t, Eq a) => Eq (Term t a) where
  Loc _ l      == r            = l == r
  l            == Loc _ r      = l == r

  Remember _ l == r            = l == r -- ?
  l            == Remember _ r = l == r -- ?

  Var a        == Var b        = a == b
  Sig e t      == Sig e' t'    = e == e' && t == t'
  Lam p b      == Lam p' b'    = p == p' && b == b'
  HardTerm t   == HardTerm t'  = t == t'
  Case b as    == Case b' as'  = b == b' && as == as'

instance Bitraversable Term where
  bitraverse f g  t0 = tm t0 where
    pt = bitraverse f
    stm = bitraverseScope f g
    tm (Var a)        = Var <$> g a
    tm (Sig e t)      = Sig <$> tm e <*> f t
    tm (Lam p b)      = Lam <$> pt p <*> stm b
    tm (HardTerm t)   = pure (HardTerm t)
    tm (l :$ r)       = (:$) <$> tm l <*> tm r
    tm (Loc r b)      = Loc r <$> tm b
    tm (Remember i b) = Remember i <$> tm b
    tm (Case b as)    = Case <$> tm b <*> traverse (bitraverse f g) as
  {-# INLINE bitraverse #-}

instance Eq t => Eq1 (Term t) where (==#) = (==)
instance Show t => Show1 (Term t) where showsPrec1 = showsPrec

instance Eq2 Term where (==##) = (==)
instance Show2 Term where showsPrec2 = showsPrec

bindTerm :: (t -> t') -> (a -> Term t' b) -> Term t a -> Term t' b
bindTerm _ g (Var a) = g a
bindTerm f g (l :$ r) = bindTerm f g l :$ bindTerm f g r
bindTerm f g (Sig e t) = Sig (bindTerm f g e) (f t)
bindTerm _ _ (HardTerm t) = HardTerm t
bindTerm f g (Lam p (Scope b)) = Lam (f <$> p) (Scope (bimap f (fmap (bindTerm f g)) b))
bindTerm f g (Loc r b) = Loc r (bindTerm f g b)
bindTerm f g (Remember i b) = Remember i (bindTerm f g b)
bindTerm f g (Case b as) = Case (bindTerm f g b) (bindAlt f g <$> as)

bindAlt :: (t -> t') -> (a -> Term t' b) -> Alt t a -> Alt t' b
bindAlt _ _ _ = error "meh"

instance Applicative (Term t) where
  pure = Var
  (<*>) = ap

instance Monad (Term t) where
  return = Var
  m >>= g = bindTerm id g m

------------------------------------------------------------------------------
-- Variables
------------------------------------------------------------------------------

instance HasKindVars t t' k k' => HasKindVars (Term t a) (Term t' a) k k' where
  kindVars f = bitraverse (kindVars f) pure

instance HasTypeVars t t' tv tv' => HasTypeVars (Term t a) (Term t' a) tv tv' where
  typeVars f = bitraverse (typeVars f) pure

class HasTermVars s t a b | s -> a, t -> b, s b -> t, t a -> s where
  termVars :: Traversal s t a b

instance HasTermVars (Term t a) (Term t b) a b where
  termVars = traverse

instance HasTermVars s t a b => HasTermVars [s] [t] a b where
  termVars = traverse.termVars

instance HasTermVars s t a b => HasTermVars (IntMap s) (IntMap t) a b where
  termVars = traverse.termVars

instance HasTermVars s t a b => HasTermVars (Map k s) (Map k t) a b where
  termVars = traverse.termVars

