{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}

{-# OPTIONS_GHC -Wno-orphans #-}

module Vehicle.Core.Parse
  ( parseText
  , parseFile
  ) where

import Data.Text (Text)
import qualified Data.Text.IO as T
import System.Exit (exitFailure)
import Control.Monad.Except (MonadError(..))

import Vehicle.Core.Abs as B
import Vehicle.Core.Par (pProg, myLexer)
import Vehicle.Core.AST as V hiding (Name)
import Vehicle.Prelude

--------------------------------------------------------------------------------
-- "Parsed" type synonyms

type PTree = V.Tree (K Symbol) (K Provenance)
type PKind = V.Kind (K Symbol) (K Provenance)
type PType = V.Type (K Symbol) (K Provenance)
type PTArg = V.TArg (K Symbol) (K Provenance)
type PExpr = V.Expr (K Symbol) (K Provenance)
type PEArg = V.EArg (K Symbol) (K Provenance)
type PDecl = V.Decl (K Symbol) (K Provenance)
type PProg = V.Prog (K Symbol) (K Provenance)

--------------------------------------------------------------------------------
-- Parsing

parseText :: Text -> Either String PProg
parseText txt = case pProg (myLexer txt) of
  Left v  -> Left v
  Right p -> case conv p of
    Left  u -> Left $ show u
    Right r -> Right r

parseFile :: FilePath -> IO PProg
parseFile file = do
  contents <- T.readFile file
  case parseText contents of
    Left err -> do putStrLn err; exitFailure
    Right ast -> return ast

--------------------------------------------------------------------------------
-- Conversion from BNFC AST
--
-- We convert from the simple AST generated automatically by BNFC to our
-- more complicated internal version of the AST which allows us to annotate
-- terms with sort-dependent types.
--
-- While doing this, we
--
--   1) extract the positions from the tokens generated by BNFC and convert them
--   into `Provenance` annotations.
--
--   2) convert the builtin strings into `Builtin`s

-- * Can extract provenance from

instance KnownSort sort => HasProvenance (PTree sort) where
  prov = unK . annotation

-- * Conversion

class Convert vf vc where
  conv :: MonadConv m => vf -> m vc

type MonadConv m = MonadError BuiltinError m

-- |Type of errors thrown by builtin checking.
newtype BuiltinError
  = UnknownBuiltin Token
  deriving (Show)

--------------------------------------------------------------------------------
-- Builtins

unKindBuiltin :: KindBuiltin -> B.Builtin
unKindBuiltin (MkKindBuiltin b) = b

unTypeBuiltin :: TypeBuiltin -> B.Builtin
unTypeBuiltin (MkTypeBuiltin b) = b

unExprBuiltin :: ExprBuiltin -> B.Builtin
unExprBuiltin (MkExprBuiltin b) = b

instance HasProvenance KindBuiltin where
  prov = tkProvenance . unKindBuiltin

instance HasProvenance TypeBuiltin where
  prov = tkProvenance . unTypeBuiltin

instance HasProvenance ExprBuiltin where
  prov = tkProvenance . unExprBuiltin

instance Convert KindBuiltin (V.Builtin 'KIND) where
  conv = findBuiltin builtinKinds . unKindBuiltin

instance Convert TypeBuiltin (V.Builtin 'TYPE) where
  conv = findBuiltin builtinTypes . unTypeBuiltin

instance Convert ExprBuiltin (V.Builtin 'EXPR) where
  conv = findBuiltin builtinExprs . unExprBuiltin

findBuiltin ::
  (MonadError BuiltinError m) =>
  [(Symbol, V.Builtin sort)] ->
  B.Builtin ->
  m (V.Builtin sort)
findBuiltin builtins tk = case lookup (tkSymbol tk) builtins of
  Nothing -> throwError (UnknownBuiltin (toToken tk))
  Just op -> return op

builtinKinds :: [(Symbol, V.Builtin 'KIND)]
builtinKinds =
  [ "->"   |-> KFun
  , "Type" |-> KType
  , "Dim"  |-> KDim
  , "List" |-> KDimList
  ]

builtinTypes :: [(Symbol, V.Builtin 'TYPE)]
builtinTypes =
  [ "->"     |-> TFun
  , "Bool"   |-> TBool
  , "Prop"   |-> TProp
  , "Int"    |-> TInt
  , "Real"   |-> TReal
  , "List"   |-> TList
  , "Tensor" |-> TTensor
  , "+"      |-> TAdd
  , "::"     |-> TCons
  ]

builtinExprs :: [(Symbol, V.Builtin 'EXPR)]
builtinExprs =
  [ "if"    |-> EIf
  , "=>"    |-> EImpl
  , "and"   |-> EAnd
  , "or"    |-> EOr
  , "not"   |-> ENot
  , "True"  |-> ETrue
  , "False" |-> EFalse
  , "=="    |-> EEq
  , "!="    |-> ENeq
  , "<="    |-> ELe
  , "<"     |-> ELt
  , ">="    |-> EGe
  , ">"     |-> EGt
  , "*"     |-> EMul
  , "/"     |-> EDiv
  , "-"     |-> ESub
  -- Negation is changed from "-" to "~" during elaboration.
  , "~"     |-> ENeg
  , "!"     |-> EAt
  , "::"    |-> ECons
  , "all"   |-> EAll
  , "any"   |-> EAny
  ]

--------------------------------------------------------------------------------
-- AST

instance Convert B.Kind PKind where
  conv = \case
    B.KApp k1 k2 -> op2 V.KApp <$> conv k1 <*> conv k2
    B.KCon c     -> V.KCon (K (prov c)) <$> conv c

instance Convert B.Type PType where
  conv = \case
    B.TForall n t    -> op2 V.TForall <$> conv n <*> conv t
    B.TApp t1 t2     -> op2 V.TApp <$> conv t1 <*> conv t2
    B.TVar n         -> conv n
    B.TCon c         -> V.TCon (K (prov c)) <$> conv c
    B.TLitDim d      -> return $ V.TLitDim mempty d
    B.TLitDimList ts -> op1 V.TLitDimList <$> traverse conv ts

instance Convert B.TypeName PType where
  conv (MkTypeName n) = return $ V.TVar (K (tkProvenance n)) (K (tkSymbol n))

instance Convert B.TypeBinder PTArg where
  conv (MkTypeBinder n) = return $ V.TArg (K (tkProvenance n)) (K (tkSymbol n))

instance Convert B.Expr PExpr where
  conv = \case
    B.EAnn e t     -> op2 V.EAnn <$> conv e <*> conv t
    B.ELet n e1 e2 -> op3 V.ELet <$> conv n <*> conv e1 <*> conv e2
    B.ELam n e     -> op2 V.ELam <$> conv n <*> conv e
    B.EApp e1 e2   -> op2 V.EApp <$> conv e1 <*> conv e2
    B.EVar n       -> conv n
    B.ETyApp e t   -> op2 V.ETyApp <$> conv e <*> conv t
    B.ETyLam n e   -> op2 V.ETyLam <$> conv n <*> conv e
    B.ECon c       -> V.ECon (K (prov c)) <$> conv c
    B.ELitInt i    -> return $ V.ELitInt mempty i
    B.ELitReal r   -> return $ V.ELitReal mempty r
    B.ELitSeq es   -> op1 V.ELitSeq <$> traverse conv es

instance Convert B.ExprName PExpr where
  conv (MkExprName n) = return $ V.EVar (K (tkProvenance n)) (K (tkSymbol n))

instance Convert B.ExprBinder PEArg where
  conv (MkExprBinder n) = return $ V.EArg (K (tkProvenance n)) (K (tkSymbol n))

instance Convert B.Decl PDecl where
  conv = \case
    B.DeclNetw n t   -> op2 V.DeclNetw <$> conv n <*> conv t
    B.DeclData n t   -> op2 V.DeclData <$> conv n <*> conv t
    B.DefType n ns t -> op3 V.DefType  <$> conv n <*> traverse conv ns <*> conv t
    B.DefFun n t e   -> op3 V.DefFun   <$> conv n <*> conv t <*> conv e

instance Convert B.Prog PProg where
  conv (B.Main ds) = op1 V.Main <$> traverse conv ds

op1 :: (HasProvenance a)
    => (K Provenance sort -> a -> PTree sort)
    -> a -> PTree sort
op1 mk t = mk (K (prov t)) t

op2 :: (KnownSort sort, HasProvenance a, HasProvenance b)
    => (K Provenance sort -> a -> b -> PTree sort)
    -> a -> b -> PTree sort
op2 mk t1 t2 = mk (K (prov t1 <> prov t2)) t1 t2

op3 :: (KnownSort sort, HasProvenance a, HasProvenance b, HasProvenance c)
    => (K Provenance sort -> a -> b -> c -> PTree sort)
    -> a -> b -> c -> PTree sort
op3 mk t1 t2 t3 = mk (K (prov t1 <> prov t2 <> prov t3)) t1 t2 t3