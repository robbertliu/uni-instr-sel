--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstructionSelection.CPModel.Base
-- Copyright   : (c) Gabriel Hjort Blindell 2013-2014
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Contains the data structures representing the data for the CP model.
--
--------------------------------------------------------------------------------

module Language.InstructionSelection.CPModel.Base where

import Language.InstructionSelection.Constraints
import Language.InstructionSelection.Graphs
  ( BBLabel (..)
  , Domset (..)
  , NodeID (..)
  )
import Language.InstructionSelection.Patterns.IDs
  ( InstructionID
  , PatternID
  , PatternInstanceID
  )
import Language.InstructionSelection.TargetMachine.IDs
import Language.InstructionSelection.Utils (Natural)



--------------
-- Data types
--------------

-- | Wrapper for all model parameters.

data CPModelParams
    = CPModelParams {
          funcData :: FunctionGraphData
        , patInstData :: [PatternInstanceData]
        , machData :: MachineData
      }
    deriving (Show)

-- | Describes the necessary function graph data.

data FunctionGraphData
    = FunctionGraphData {

          -- | The action nodes in the function graph.

          funcActionNodes :: [NodeID]

          -- | The data nodes in the function graph.

        , funcDataNodes :: [NodeID]

          -- | The state nodes in the function graph.

        , funcStateNodes :: [NodeID]

          -- | The label nodes in the function graph, along with their dominator
          -- sets.

        , funcLabelDoms :: [Domset NodeID]

          -- | The root label, or entry point into the function.

        , funcRootLabel :: NodeID

          -- | The basic block labels of the label nodes.

        , funcBBLabels :: [BBLabelData]

          -- | The function constraints, if any.

        , funcConstraints :: [Constraint]

      }
    deriving (Show)

-- | Associates a basic block label with a label node.

data BBLabelData
    = BBLabelData {

          -- | The node ID of the label node.

          labNode :: NodeID

          -- | The basic block label of the label node.

        , labBB :: BBLabel

      }
    deriving (Show)

-- | Describes the necessary pattern instance data.

data PatternInstanceData
    = PatternInstanceData {

          -- | The instruction ID of this pattern instance.

          patInstructionID :: InstructionID

          -- | The pattern ID of this pattern instance.

        , patPatternID :: PatternID

          -- | The matchset ID of this pattern instance.

        , patInstanceID :: PatternInstanceID

          -- | The action nodes in the function graph which are covered by this
          -- pattern instance.

        , patActionNodesCovered :: [NodeID]

          -- | The data nodes in the function graph which are defined by this
          -- pattern instance.

        , patDataNodesDefined :: [NodeID]

          -- | The data nodes in the function graph which are used by this
          -- pattern instance. Unlike 'patDataNodesUsedByPhis', this list
          -- contains all data nodes used by any action node appearing in this
          -- pattern instance.

        , patDataNodesUsed :: [NodeID]

          -- | The data nodes in the function graph which are used by phi nodes
          -- appearing this pattern instance. This information is required
          -- during instruction emission in order to break cyclic data
          -- dependencies.

        , patDataNodesUsedByPhis :: [NodeID]

          -- | The state nodes in the function graph which are defined by this
          -- pattern instance.

        , patStateNodesDefined :: [NodeID]

          -- | The state nodes in the function graph which are used by this
          -- pattern instance.

        , patStateNodesUsed :: [NodeID]

          -- | The label nodes in the function graph which are referred to by
          -- this pattern instance.

        , patLabelNodesReferred :: [NodeID]

          -- | The pattern-specific constraints, if any. All node IDs used in
          -- the patterns refer to nodes in the function graph (not the pattern
          -- graph).

        , patConstraints :: [Constraint]

          -- | Whether the use-def-dom constraints apply to this pattern
          -- instance. This will typically always be set to 'True' for all
          -- patterns instances except those of the generic phi patterns.

        , patAUDDC :: Bool

          -- | The size of the instruction associated with this pattern
          -- instance.

        , patCodeSize :: Integer

          -- | The latency of the instruction associated with this pattern
          -- instance.

        , patLatency :: Integer

          -- | Maps an 'AssemblyID', which is denoted as the index into the
          -- list, that appear in the 'AssemblyString' of the instruction, to a
          -- particular data node in the function graph according to the
          -- pattern's operation structure and matchset. See also
          -- 'InstPattern.patAssIDMaps'.

        , patAssIDMaps :: [NodeID]

      }
    deriving (Show)

-- | Contains the necessary target machine data.

data MachineData
    = MachineData {

          -- | The registers in the target machine.

          machRegisters :: [RegisterID]

      }
    deriving (Show)

-- | Contains the data for a solution to the CP model.

data CPSolutionData
    = CPSolutionData {

          -- | The basic block (given as array indices) to which a particular
          -- pattern instance was allocated. An array index for a pattern
          -- instance corresponds to an index into the list.

          bbAllocsForPIs :: [Natural]

          -- | Indicates whether a particular pattern instance was selected. An
          -- array index for a pattern instance corresponds to an index into the
          -- list.

        , isPISelected :: [Bool]

          -- | The order of basic blocks. An array index for a label node in the
          -- function graph corresponds to an index into the list.

        , orderOfBBs :: [Natural]

          -- | Indicates whether a register has been selected for a particular
          -- data node. An array index for a data node corresponds to an index
          -- into the list.

        , hasDataNodeRegister :: [Bool]

          -- | Specifies the register selected for a particular data node. An
          -- array index for a data node corresponds to an index into the list.
          -- The register value is only valid if the corresponding value in
          -- 'hasDataNodeRegister' is set to 'True'.

        , regsSelectedForDataNodes :: [RegisterID]

          -- | Indicates whether an immediate value has been assigned to a
          -- particular data node. An array index for a data node corresponds to
          -- an index into the list.

        , hasDataNodeImmValue :: [Bool]

          -- | Specifies the immediate value assigned to a particular data
          -- node. An array index for a data node corresponds to an index into
          -- the list. The immediate value is only valid if the corresponding
          -- value in 'hasDataNodeImmValue' is set to 'True'.

        , immValuesOfDataNodes :: [Integer]

      }
    deriving (Show)

-- | Contains the post-processing parameters.

data PostParams
    = PostParams {

          -- | The CP model parameters.

          modelParams :: CPModelParams

          -- | The array indices-to-pattern instance id mappings.

        , arrInd2PattInstIDs :: [PatternInstanceID]

          -- | The array indices-to-label node ID mappings.

        , arrInd2LabNodeIDs :: [NodeID]

          -- | The array indices-to-data node ID mappings.

        , arrInd2DataNodeIDs :: [NodeID]

      }
    deriving (Show)
