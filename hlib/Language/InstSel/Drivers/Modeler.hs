--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstSel.Drivers.Modeler
-- Copyright   : (c) Gabriel Hjort Blindell 2014
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Takes a function graph, a set of pattern matches as input, and produces the
-- data needed for the CP model.
--
--------------------------------------------------------------------------------

module Language.InstSel.Drivers.Modeler
  ( run )
where


import Language.InstSel.Drivers.Base
import Language.InstSel.CPModel.ParamMaker
import Language.InstSel.TargetMachines.Targets
  ( getTargetMachine )
import Language.InstSel.TargetMachines.PatternMatching
  ( MatchsetInfo (..) )
import Language.InstSel.Utils.JSON

import Data.Maybe
  ( fromJust
  , isNothing
  )



-------------
-- Functions
-------------

run
  :: String
     -- ^ The function in JSON format.
  -> String
     -- ^ The instruction pattern matches in JSON format.
  -> IO [Output]
     -- ^ The produced output.
run f_str m_str =
  do let f_res = fromJson f_str
         m_res = fromJson m_str
     when (isLeft f_res) $
       reportError $ fromLeft f_res
     when (isLeft m_res) $
       reportError $ fromLeft m_res
     let function = fromRight f_res
         msinfo = fromRight m_res
         matches = msiMatches msinfo
         target_id = msiTarget msinfo
         mtarget = getTargetMachine target_id
     when (isNothing mtarget) $
       reportError $ "No target machine with ID '" ++ show target_id ++ "'"
     let target = fromJust mtarget
         params = mkParams target function matches
     return [toOutputWithoutID $ toJson params]