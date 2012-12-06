{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
--------------------------------------------------------------------
-- |
-- Module    :  Ermine.Pat
-- Copyright :  (c) Edward Kmett
-- License   :  BSD3
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable
--------------------------------------------------------------------
module Ermine.Pat
  ( Pat(..)
  ) where

import Data.Foldable
import Data.Traversable
import Ermine.Prim

-- | Patterns used by 'Term' and 'Core'.
data Pat t
  = VarP
  | SigP t             -- ^ not used by 'Core'
  | WildcardP
  | AsP (Pat t)
  | StrictP (Pat t)
  | LazyP (Pat t)
  | PrimP Prim [Pat t]
  deriving (Eq, Show, Functor, Foldable, Traversable)