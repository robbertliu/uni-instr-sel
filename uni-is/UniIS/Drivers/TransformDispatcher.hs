{-|
Copyright   :  Copyright (c) 2012-2016, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

Contributing authors:
  Roberto Castaneda Lozano <rcas@sics.se>

-}

module UniIS.Drivers.TransformDispatcher
  ( run )
where

import UniIS.Drivers.DispatcherTools
import qualified UniIS.Drivers.TransformFunctionGraph as TransformFunctionGraph
import qualified UniIS.Drivers.TransformCPModel as TransformCPModel
import qualified UniIS.Drivers.TransformCPSolution as TransformCPSolution



-------------
-- Functions
-------------

run :: Options -> IO [Output]
run opts = dispatch (transformAction opts) opts

dispatch :: TransformAction -> Options -> IO [Output]
dispatch a opts
  | a == TransformNothing =
      reportErrorAndExit "No transform action provided."
  | a `elem` [ CopyExtendFunctionGraph
             , BranchExtendFunctionGraph
             , CombineConstantsInFunctionGraph
             , AlternativeExtendFunctionGraph
             ] =
      do content <- loadFunctionFileContent opts
         function <- loadFromJson content
         TransformFunctionGraph.run a function
  | a `elem` [LowerHighLevelCPModel] =
      do m_content <- loadModelFileContent opts
         ai_maps <- loadArrayIndexMaplistsFromJson opts
         TransformCPModel.run a m_content ai_maps
  | a `elem` [RaiseLowLevelCPSolution] =
      do m_content <- loadModelFileContent opts
         sol_content <- loadSolutionFileContent opts
         ai_content <- loadArrayIndexMaplistsFileContent opts
         ai_maps <- loadFromJson ai_content
         TransformCPSolution.run a sol_content m_content ai_maps
  | otherwise =
      reportErrorAndExit "TransformDispatcher: unsupported action"
