module Oden.Compiler.Validation where

import           Oden.Core
import           Oden.Identifier
import           Oden.SourceInfo
import           Oden.Type.Polymorphic

import           Control.Monad.Except
import           Control.Monad.Reader
import           Control.Monad.State

import qualified Data.Set        as Set

data ValidationError = Redefinition SourceInfo Name
                     deriving (Show, Eq, Ord)

data ValidationWarning = ValueDiscarded (Expr Type)
                       deriving (Show, Eq, Ord)

type Validate = ReaderT
                (Set.Set Name)
                (StateT [ValidationWarning]
                        (Except ValidationError))

errorIfDefined :: Name -> SourceInfo -> Validate ()
errorIfDefined name si = do
  scope <- ask
  when (Set.member name scope) $
    throwError (Redefinition si name)

withName :: Name -> Validate a -> Validate a
withName = local . Set.insert

validateExpr :: Expr Type -> Validate ()
validateExpr Symbol{} = return ()
validateExpr (Op _ _ lhs rhs _) = do
  validateExpr lhs
  validateExpr rhs
validateExpr (Application _ f arg _) = do
  validateExpr f
  validateExpr arg
validateExpr (NoArgApplication _ f _) =
  validateExpr f
validateExpr (UncurriedFnApplication _ f args _) = do
  validateExpr f
  mapM_ validateExpr args
validateExpr (Fn _ (Binding si name) body _) =  do
  errorIfDefined name si
  withName name (validateExpr body)
validateExpr (NoArgFn _ body _) =
  validateExpr body
validateExpr (Let _ (Binding si name) value body _) = do
  errorIfDefined name si
  validateExpr value
  withName name (validateExpr body)
validateExpr Literal{} = return ()
validateExpr (Tuple _ f s r _) =
  mapM_ validateExpr (f:s:r)
validateExpr (Slice _ exprs _) =
  mapM_ validateExpr exprs
validateExpr (If _ c t e _) = do
  validateExpr c
  validateExpr t
  validateExpr e
validateExpr (Block _ exprs _) =
  mapM_ validateExpr exprs

validatePackage :: Package -> Validate ()
validatePackage (Package _ _ definitions) = validateSeq definitions
  where
  validateSeq [] = return ()
  validateSeq (Definition si name (_, expr) : ds) = do
    errorIfDefined name si
    withName name $ do
      validateExpr expr
      validateSeq ds

validate :: Package -> Either ValidationError [ValidationWarning]
validate pkg =
  runExcept (execStateT (runReaderT (validatePackage pkg) Set.empty) [])