--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstrSel.TargetMachines.Generators.HaskellCodeGenerator
-- Copyright   : (c) Gabriel Hjort Blindell 2013-2015
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Takes a target machine and generators corresponding Haskell code.
--
--------------------------------------------------------------------------------

module Language.InstrSel.TargetMachines.Generators.HaskellCodeGenerator where

import Language.InstrSel.TargetMachines.Base
  ( TargetMachine (tmID)
  , fromTargetMachineID
  )
import Language.InstrSel.Utils
  ( replace )

import Language.Haskell.Exts



-------------
-- Functions
-------------

-- | Takes a 'TargetMachine' and generates corresponding Haskell source code.
-- The source code is then wrapped inside a module with name equal to the
-- 'TargetMachineID'.
generateModule :: TargetMachine -> String
generateModule tm =
  let renameFuncs str = replace "mkGraph" "I.mkGraph" str
      tm_id = fromTargetMachineID (tmID tm)
      boiler_src = "-----------------------------------------------------------\
                   \---------------------\n\
                   \-- |\n\
                   \-- Module      : UniIS.Targets." ++ tm_id ++ "\n\
                   \-- Stability   : experimental\n\
                   \-- Portability : portable\n\
                   \--\n\
                   \-- THIS MODULE HAS BEEN AUTOGENERATED!\n\
                   \--\n\
                   \-----------------------------------------------------------\
                   \---------------------\n\n"
      header_src = "module UniIS.Targets." ++ tm_id ++ "\n\
                   \  ( theTM )\n\
                   \where\n\n\
                   \import Language.InstrSel.Constraints\n\
                   \import Language.InstrSel.DataTypes\n\
                   \import Language.InstrSel.Graphs\n\
                   \import Language.InstrSel.Functions.IDs\n\
                   \import qualified Data.Graph.Inductive as I\n\
                   \import Language.InstrSel.OpStructures\n\
                   \import Language.InstrSel.OpTypes\n\
                   \import Language.InstrSel.TargetMachines\n\
                   \import Language.InstrSel.Utils\n\
                   \import Prelude \n\
                   \  hiding\n\
                   \  ( LT, GT )\n\n"
      tm_func_src = "theTM :: TargetMachine\n\
                    \theTM = " ++ (renameFuncs $ show tm)
      res = parseFileContents $ header_src ++ tm_func_src
      prettify m = prettyPrintStyleMode (style { lineLength = 80 })
                                        defaultMode m
  in case res
     of (ParseOk m) -> boiler_src ++ prettify m
        (ParseFailed line msg) -> error $ "generateModule: parsing failed at "
                                         ++ show line ++ ": " ++ msg
