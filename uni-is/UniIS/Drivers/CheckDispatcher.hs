{-|
Copyright   :  Copyright (c) 2012-2016, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

-}

module UniIS.Drivers.CheckDispatcher
  ( run )
where

import UniIS.Drivers.DispatcherTools
import qualified UniIS.Drivers.CheckFunctionGraph as CheckFunctionGraph
import qualified UniIS.Drivers.CheckIntegrity as CheckIntegrity

import Language.InstrSel.TargetMachines.PatternMatching
  ( PatternMatchset (pmTarget) )



-------------
-- Functions
-------------

run :: Options -> IO [Output]
run opts = dispatch (checkAction opts) opts

dispatch :: CheckAction -> Options -> IO [Output]
dispatch a opts
  | a == CheckNothing =
      reportErrorAndExit "No check action provided."
  | a `elem` [ CheckFunctionGraphCoverage ] =
      do function <- loadFunctionFromJson opts
         matchset <- loadPatternMatchsetFromJson opts
         CheckFunctionGraph.run a function matchset Nothing
  | a `elem` [ CheckFunctionGraphLocationOverlap ] =
      do function <- loadFunctionFromJson opts
         matchset <- loadPatternMatchsetFromJson opts
         tm <- loadTargetMachine $ pmTarget matchset
         CheckFunctionGraph.run a function matchset (Just tm)
  | a `elem` [ CheckFunctionIntegrity ] =
      do function <- loadFunctionFromJson opts
         CheckIntegrity.run a (Just function) Nothing
  | a `elem` [ CheckPatternIntegrity ] =
      do tmid <- getSelectedTargetMachineID opts
         tm <- loadTargetMachine tmid
         iid <- getSelectedInstructionID opts
         pid <- getSelectedPatternID opts
         pat <- loadInstrPattern tm iid pid
         CheckIntegrity.run a Nothing (Just pat)
  | otherwise =
      reportErrorAndExit "CheckDispatcher: unsupported action"
