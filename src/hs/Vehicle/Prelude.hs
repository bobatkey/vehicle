{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE TypeFamilies    #-}
{-# LANGUAGE TypeOperators   #-}
{-# LANGUAGE PolyKinds       #-}

module Vehicle.Prelude
  ( module X
  , (|->)
  , (:*:)(..)
  , type DecIn
  , type In
  , K(..)
  , O(..)
  , rangeStart
  ) where

import Data.Range

import Vehicle.Prelude.Token as X
import Vehicle.Prelude.Sort as X
import Vehicle.Prelude.Provenance as X

infix 1 |->

-- | Useful for writing association lists.
(|->) :: a -> b -> (a, b)
(|->) = (,)

-- | Indexed product.
data (:*:) (f :: k -> *) (g :: k -> *) (x :: k) = (:*:) { ifst :: f x, isnd :: g x }
  deriving (Eq, Ord, Show)

instance (Semigroup (f x), Semigroup (g x)) => Semigroup ((f :*: g) x) where
  (x1 :*: y1) <> (x2 :*: y2) = (x1 <> x2) :*: (y1 <> y2)

instance (Monoid (f x), Monoid (g x)) => Monoid ((f :*: g) x) where
  mempty = mempty :*: mempty

-- |
type family DecIn (x :: k) (xs :: [k]) :: Bool where
  DecIn x '[]       = 'False
  DecIn x (x ': xs) = 'True
  DecIn x (y ': xs) = DecIn x xs

-- |
type In (x :: k) (xs :: [k]) = DecIn x xs ~ 'True

-- |Type-level constant function.
newtype K (a :: *) (b :: k) = K { unK :: a }
  deriving (Eq, Ord, Show)

instance Semigroup a => Semigroup (K a sort) where
  K x <> K y = K (x <> y)

instance Monoid a => Monoid (K a sort) where
  mempty = K mempty

-- |Type-level function composition.
newtype O (g :: * -> *) (f :: k -> *) (a :: k) = O { unO :: g (f a) }


-- |Attempts to extract the first element from a bound
boundStart :: Bound a -> Maybe a
boundStart (Bound v Inclusive)= Just v
boundStart (Bound _v Exclusive)= Nothing

-- |Attempts to extract the first element in a range
rangeStart :: Range a -> Maybe a
rangeStart (SingletonRange a)          = Just a
rangeStart (SpanRange lb _ub)          = boundStart lb
rangeStart (LowerBoundRange b)         = boundStart b
rangeStart (UpperBoundRange _)         = Nothing
rangeStart InfiniteRange               = Nothing