
module Vehicle.Core.Compile.Metas
  ( MetaSet
  , prettyMetas
  , prettyMetaSubst
  , MetaSubstitution
  , MetaSubstitutable(..)
  ) where

import Control.Monad.Reader (Reader, runReader, ask)

import Data.IntMap (IntMap)
import Data.IntMap qualified as IntMap
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Prettyprinter (Doc, Pretty(..), (<+>), concatWith, softline, group, align, line)

import Vehicle.Core.AST
import Vehicle.Core.Print.Core ()

type MetaSet = IntSet

prettyMetas :: MetaSet -> Doc a
prettyMetas = pretty . IntSet.toList

type MetaSubstitution = IntMap CheckedExpr

prettyMetaSubst :: MetaSubstitution -> Doc a
prettyMetaSubst msubst =
  "{" <+> align (group
    (concatWith (\x y -> x <> ";" <> line <> y)
      (map (\(i, t') -> "?" <> pretty i <+> ":=" <+> pretty t') (IntMap.toAscList msubst))
     <> softline <> "}"))

class MetaSubstitutable a where
  substM :: a -> Reader MetaSubstitution a

  substMetas :: MetaSubstitution -> a -> a
  substMetas s e = runReader (substM e) s

instance MetaSubstitutable a => MetaSubstitutable (a, a) where
  substM (e1, e2) = do
    e1' <- substM e1
    e2' <- substM e2
    return (e1', e2')

instance MetaSubstitutable CheckedArg where
  substM (Arg p v e) = Arg p v <$> substM e

instance MetaSubstitutable CheckedBinder where
  substM (Binder p v n t) = Binder p v n <$> substM t

instance MetaSubstitutable CheckedAnn where
  substM (RecAnn e ann) = RecAnn <$> substM e <*> pure ann

instance MetaSubstitutable CheckedExpr where
  substM = \case
    Type l                   -> return (Type l)
    Constraint               -> return Constraint
    Hole p name              -> return (Hole p name)
    Builtin ann op           -> Builtin <$> substM ann <*> pure op
    Literal ann l            -> Literal <$> substM ann <*> pure l
    Seq     ann es           -> Seq     <$> substM ann <*> traverse substM es
    Ann     ann term typ     -> Ann     <$> substM ann <*> substM term   <*> substM typ
    App     ann fun arg      -> App     <$> substM ann <*> substM fun    <*> substM arg
    Pi      ann binder res   -> Pi      <$> substM ann <*> substM binder <*> substM res
    Let     ann e1 binder e2 -> Let     <$> substM ann <*> substM e1     <*> substM binder <*> substM e2
    Lam     ann binder e     -> Lam     <$> substM ann <*> substM binder <*> substM e
    Var     ann v            -> Var     <$> substM ann <*> pure v

    Meta    ann m -> do
      subst <- ask
      case IntMap.lookup m subst of
        Nothing -> Meta <$> substM ann <*> pure m
        Just e  -> return e

instance MetaSubstitutable CheckedDecl where
  substM = \case
    DeclNetw p ident t   -> DeclNetw p ident <$> substM t
    DeclData p ident t   -> DeclData p ident <$> substM t
    DefFun   p ident t e -> DefFun   p ident <$> substM t <*> substM e

instance MetaSubstitutable CheckedProg where
  substM (Main ds) = Main <$> traverse substM ds