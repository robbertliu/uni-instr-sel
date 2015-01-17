--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstSel.Drivers.MakeDispatcher
-- Copyright   : (c) Gabriel Hjort Blindell 2014
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Driver for dispatching make commands.
--
--------------------------------------------------------------------------------

module Language.InstSel.Drivers.MakeDispatcher
  ( run )
where

import Language.InstSel.Drivers.DispatcherTools
import qualified Language.InstSel.Drivers.MakeArrayIndexMapInfo as MArray
import qualified Language.InstSel.Drivers.MakeFunctionFromLLVM as MLLVM
import qualified Language.InstSel.Drivers.MakeMatchsetInfo as MMatch



-------------
-- Functions
-------------

run :: Options -> IO [Output]
run opts = dispatch (makeAction opts) opts

dispatch :: MakeAction -> Options -> IO [Output]
dispatch a opts
  | a == MakeNothing =
      reportError "No make action provided."
  | a `elem` [MakeFunctionGraphFromLLVM] =
      do content <- loadFunctionFileContent opts
         MLLVM.run a content
  | a `elem` [MakeMatchsetInfo] =
      do function <- loadFunctionFromJson opts
         target <- loadTargetMachine opts
         MMatch.run a function target
  | a `elem` [MakeArrayIndexMapInfo] =
      do function <- loadFunctionFromJson opts
         matchset <- loadMatchsetInfoFromJson opts
         MArray.run a function matchset
  | otherwise =
      reportError "MakeDispatcher: unsupported action"
