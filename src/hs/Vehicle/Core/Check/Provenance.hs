{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE ScopedTypeVariables  #-}

module Vehicle.Core.Check.Provenance where

import           Control.Monad.Writer
import           Data.Functor.Foldable (fold)
import           Data.Range (Range(..), (+=+))
import qualified Data.Range as Range
import           Data.Semigroup (Semigroup(..))
import           Data.Text (Text)
import qualified Data.Text as T
import           Vehicle.Core.Check.Core
import           Vehicle.Core.Type
import           Vehicle.Prelude


newtype Provenance = Provenance { fromProvenance :: [Range Position] }

instance Semigroup Provenance where
  r1 <> r2 = Provenance $ fromProvenance r1 `Range.union` fromProvenance r2

instance Monoid Provenance where
  mempty = Provenance []

-- |Get the provenance for a single token.
tkProvenance :: IsToken a => a -> Provenance
tkProvenance tk = Provenance [begin +=+ end]
  where
    begin = tkPos tk
    end   = (line begin, column begin + tkLength tk)


-- |Takes the output produced by the writer, and feeds it back into the result.
--
-- TODO: this is rather ugly
--
knot ::
  Writer Provenance (Provenance -> Tree sort name builtin (K Provenance :*: ann)) ->
  Writer Provenance (Tree sort name builtin (K Provenance :*: ann))
knot wf = let (f, p) = runWriter wf in writer (f p, p)


-- |Save the provenance at each annotation.
saveProvenance :: forall sort name builtin ann.
  (KnownSort sort, IsToken name, IsToken builtin) =>
  Tree sort (K name) (K builtin) ann ->
  Writer Provenance (Tree sort (K name) (K builtin) (K Provenance :*: ann))

saveProvenance = case sortSing :: SSort sort of

  -- Kinds.
  SKIND -> fold $ \case
    KConF  ann op      -> knot $ do tell (tkProvenance op)
                                    return $ \p -> KCon (K p :*: ann) op
    KMetaF ann i       -> knot $ do return $ \p -> KMeta (K p :*: ann) i
    KAppF  ann wk1 wk2 -> knot $ do k1 <- wk1
                                    k2 <- wk2
                                    return $ \p -> KApp (K p :*: ann) k1 k2

  -- Types.
  STYPE -> fold $ \case
    TForallF  ann wn wt -> do n <- wn
                              t <- wt
                              tell (tkProvenance n)
                              return $ \p -> TForall (K p :*: ann) n t
    TAppF     ann t1 t2 -> undefined
    TVarF     ann n     -> undefined
    TConF     ann op    -> undefined
    TLitDimF  ann d     -> undefined
    TLitListF ann ts    -> undefined
    TMetaF    ann i     -> undefined
