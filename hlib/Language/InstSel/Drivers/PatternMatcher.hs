--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstSel.Drivers.PatternMatcher
-- Copyright   : (c) Gabriel Hjort Blindell 2014
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Takes a function file and target machine as input, and performs pattern
-- matching of all instruction patterns on the function graph.
--
--------------------------------------------------------------------------------

module Language.InstSel.Drivers.PatternMatcher
  ( run )
where

import Language.InstSel.Drivers.Base
import Language.InstSel.TargetMachines
  ( TargetMachine )
import Language.InstSel.TargetMachines.PatternMatching
  ( mkMatchsetInfo )
import Language.InstSel.Utils.JSON



-------------
-- Functions
-------------

run
  :: String
     -- ^ The function in JSON format.
  -> TargetMachine
     -- ^ The target machine.
  -> IO [Output]
     -- ^ The produced output.
run str target =
  do let res = fromJson str
     when (isLeft res) $
       reportError $ fromLeft res
     let function = fromRight res
         matches = mkMatchsetInfo function target
     return [toOutputWithoutID $ toJson matches]