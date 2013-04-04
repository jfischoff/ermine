{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
--------------------------------------------------------------------
-- |
-- Copyright :  (c) Edward Kmett and Dan Doel 2012-2013
-- License   :  BSD3
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable
--
--------------------------------------------------------------------
module Ermine.Inference.Witness
  ( Witness(Witness)
  , HasWitness(..)
  ) where

import Bound.Var
import Control.Applicative
import Control.Lens
import Data.Bifoldable
import Data.Bitraversable
import Data.Foldable
import Data.Hashable
import Data.Hashable.Extras
import Data.Typeable
import Ermine.Syntax.Core
import Ermine.Syntax.Id
import Ermine.Syntax.Kind
import Ermine.Syntax.Type
import GHC.Generics
import Prelude.Extras

data Witness k a = Witness
  { _witnessConstraints :: [Type k a]
  , _witnessRowConstraints :: [Type k a]
  , _witnessType :: !(Type k a)
  , _witnessCore :: !(Core (Var Int Id))
  } deriving (Show, Eq, Functor, Foldable, Traversable, Typeable, Generic)

makeClassy ''Witness

witnessTypes :: Traversal (Witness k a) (Witness k' b) (Type k a) (Type k' b)
witnessTypes f (Witness cs rcs t c) =
  Witness <$> traverse f cs
          <*> traverse f rcs
          <*> f t
          <*> pure c

instance HasTypeVars (Witness k a) (Witness k b) a b where
  typeVars = witnessTypes.typeVars

instance HasKindVars (Witness k a) (Witness k' a) k k' where
  kindVars = witnessTypes.kindVars

instance Eq2 Witness
instance Eq k => Eq1 (Witness k)

instance Show2 Witness
instance Show k => Show1 (Witness k)

instance Hashable2 Witness
instance Hashable k => Hashable1 (Witness k)
instance (Hashable k, Hashable a) => Hashable (Witness k a)

instance Bifunctor Witness where
  bimap = bimapDefault

instance Bifoldable Witness where
  bifoldMap = bifoldMapDefault

instance Bitraversable Witness where
  bitraverse f g = witnessTypes (bitraverse f g)