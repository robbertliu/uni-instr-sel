--------------------------------------------------------------------------------
-- |
-- Module      :  Language.InstructionSelection.ProgramModules.Base
-- Copyright   :  (c) Gabriel Hjort Blindell 2013-2014
-- License     :  BSD-style (see the LICENSE file)
--
-- Maintainer  :  ghb@kth.se
-- Stability   :  experimental
-- Portability :  portable
--
-- Contains the data types and records for representing program modules, which
-- basically consist of a list of functions. This is the format on which
-- subsequent preparation for instruction selection will build on (i.e. other
-- programs forms, such as those based on LLVM, will be converted into this
-- format).
--
-- Since only the function name is retained, the names of overloaded functions
-- must have been resolved such that each is given a unique name.
--
--------------------------------------------------------------------------------

module Language.InstructionSelection.ProgramModules.Base (
  Function (..)
) where

import Language.InstructionSelection.OpStructures



-- | The record of representing a program function.

data Function
    = Function {

          -- | The function name.

          functionName :: String

          -- | The semantics of the function.

        , functionOS :: OpStructure

      }
    deriving (Show)
