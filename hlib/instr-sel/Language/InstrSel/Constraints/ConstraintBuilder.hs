{-|
Copyright   :  Copyright (c) 2012-2016, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

-}

module Language.InstrSel.Constraints.ConstraintBuilder
  ( addFallThroughConstraints
  , addNewDataLocConstraints
  , mkFallThroughConstraints
  , mkNewDataLocConstraints
  )
where

import Language.InstrSel.Constraints.Base
import Language.InstrSel.Graphs
import Language.InstrSel.OpStructures
import Language.InstrSel.TargetMachines.IDs
  ( LocationID )



-------------
-- Functions
-------------

-- | Creates constraints using 'mkNewDataLocConstraints' and adds these (if any)
--  to the given 'OpStructure'.
addNewDataLocConstraints
  :: [LocationID]
     -- ^ List of locations to which the data can be allocated.
  -> NodeID
     -- ^ A value node.
  -> OpStructure
     -- ^ The old structure.
  -> OpStructure
     -- ^ The new structure, with the produced constraints (may be the same
     -- structure).
addNewDataLocConstraints regs d os =
  addConstraints os (mkNewDataLocConstraints regs d)

-- | Creates location constraints such that the data of a particular value node
-- must be in one of a particular set of locations.
mkNewDataLocConstraints
  :: [LocationID]
     -- ^ List of locations to which the data can be allocated.
  -> NodeID
     -- ^ A value node.
  -> [Constraint]
mkNewDataLocConstraints [reg] d =
  [ BoolExprConstraint $
    EqExpr ( Location2NumExpr $
             LocationOfValueNodeExpr $
             ANodeIDExpr d
           )
           ( Location2NumExpr $
             ALocationIDExpr reg
           )
  ]
mkNewDataLocConstraints regs d =
  [ BoolExprConstraint $
    InSetExpr ( Location2SetElemExpr $
                LocationOfValueNodeExpr $
                ANodeIDExpr d
              )
              ( LocationClassExpr $
                map ALocationIDExpr regs
              )
  ]

-- | Creates constraints using 'mkFallThroughConstraints' and adds these (if
-- any) to the given 'OpStructure'.
addFallThroughConstraints :: NodeID -> OpStructure -> OpStructure
addFallThroughConstraints l os =
  addConstraints os (mkFallThroughConstraints l)

-- | Creates constraints for enforcing a fall-through from a match to a block.
mkFallThroughConstraints
  :: NodeID
     -- ^ A block node.
  -> [Constraint]
mkFallThroughConstraints l =
  [ BoolExprConstraint $
    FallThroughFromMatchToBlockExpr $
    BlockOfBlockNodeExpr $
    ANodeIDExpr l
  ]
