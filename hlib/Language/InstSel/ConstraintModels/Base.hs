--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstSel.ConstraintModels.Base
-- Copyright   : (c) Gabriel Hjort Blindell 2013-2014
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Contains the data structures representing CP model instances and solutions to
-- these instances.
--
-- There are two kinds of instances and solutions: high-level versions, and
-- low-level versions. In a high-level version, all IDs (such as node IDs, match
-- IDs, register IDs, etc.) appearing the model are left intact. In a low-level
-- version, these IDs are instead represented as array indices. The reason for
-- having a low-level version is because this simplifies the implementation of
-- the solver backend; an ID is often used to identify a specific domain
-- variable, which are typically organized as domain variable arrays, but since
-- IDs are not required to be contiguous they cannot be used as array indices
-- directly. By lowering a high-level version into a low-level version, the IDs
-- are converted into corresponding array indices such that the array indices
-- later can be converted back into the original IDs.
--
-- In addition, low-level CP model instances have a flatter hierarchy than their
-- high-level counterparts, and information appearing in the high-level CP model
-- instance that is not strictly needed for solving is removed from the
-- low-level CP model instance.
--
--------------------------------------------------------------------------------

{-# LANGUAGE OverloadedStrings, FlexibleInstances #-}

module Language.InstSel.ConstraintModels.Base
  ( ArrayIndexMaplists (..)
  , HighLevelModel (..)
  , HighLevelBasicBlockParams (..)
  , HighLevelFunctionParams (..)
  , HighLevelMachineParams (..)
  , HighLevelMatchParams (..)
  , HighLevelSolution (..)
  , LowLevelModel (..)
  , LowLevelSolution (..)
  )
where

import Language.InstSel.ConstraintModels.IDs

import Language.InstSel.Constraints
import Language.InstSel.Graphs
  ( DomSet (..)
  , PostDomSet
  , MatchID (..)
  , NodeID (..)
  )
import Language.InstSel.Functions
  ( BasicBlockLabel (..)
  , ExecFreq (..)
  )
import Language.InstSel.TargetMachines.IDs
import Language.InstSel.Utils.JSON



--------------
-- Data types
--------------

-- | Contains a high-level CP model.
data HighLevelModel
  = HighLevelModel
      { hlFunctionParams :: HighLevelFunctionParams
      , hlMachineParams :: HighLevelMachineParams
      , hlMatchParams :: [HighLevelMatchParams]
      }
  deriving (Show)

-- | Contains the high-level function graph parameters.
data HighLevelFunctionParams
  = HighLevelFunctionParams
      { hlFunOpNodes :: [NodeID]
        -- ^ The operation nodes in the function graph.
      , hlFunEntityNodes :: [NodeID]
        -- ^ The entity nodes in the function graph.
      , hlFunLabelNodes :: [NodeID]
        -- ^ The label nodes in the function graph.
      , hlFunEntryLabelNode :: NodeID
        -- ^ The label that is the entry point into the function.
      , hlFunLabelDomSets :: [DomSet NodeID]
        -- ^ The dominator sets of the label nodes.
      , hlFunLabelPostDomSets :: [PostDomSet NodeID]
        -- ^ The postdominator sets of the label nodes.
      , hlFunDomEdges :: [(NodeID, NodeID)]
        -- ^ The dominance edges, where the first element in the tuple is the
        -- entity node and the second element is the label node.
      , hlFunPostDomEdges :: [(NodeID, NodeID)]
        -- ^ The postdominance edges, where the first element in the tuple is
        -- the entity node and the second element is the label node.
      , hlFunBasicBlockParams :: [HighLevelBasicBlockParams]
        -- ^ The basic block information.
      , hlFunEssentialOpNodes :: [NodeID]
        -- ^ Operation nodes that are essential, meaning they *must* be covered.
      , hlFunConstraints :: [Constraint]
        -- ^ The function constraints, if any. No constraint in this list may
        -- use array indices.
      }
  deriving (Show)

-- | Contains the high-level basic block information.
data HighLevelBasicBlockParams
  = HighLevelBasicBlockParams
      { hlBBLabel :: BasicBlockLabel
        -- ^ The label of this basic block.
      , hlBBLabelNode :: NodeID
        -- ^ The node ID of the label node that represents this basic block.
      , hlBBExecFrequency :: ExecFreq
        -- ^ The execution frequency of this basic block.
      }
  deriving (Show)

-- | Contains the high-level match parameters.
data HighLevelMatchParams
  = HighLevelMatchParams
      { hlMatchInstructionID :: InstructionID
        -- ^ The instruction ID of this match.
      , hlMatchPatternID :: PatternID
        -- ^ The pattern ID of this match.
      , hlMatchID :: MatchID
        -- ^ The matchset ID of this match.
      , hlMatchOpNodesCovered :: [NodeID]
        -- ^ The operations in the function graph which are covered by this
        -- match.
      , hlMatchEntityNodesDefined :: [NodeID]
        -- ^ The entities in the function graph which are defined by this match.
      , hlMatchEntityNodesUsed :: [NodeID]
        -- ^ The entities in the function graph which are used by this
        -- match.
      , hlMatchEntryLabelNode :: Maybe NodeID
        -- ^ The label node in the function graph that appears as entry label
        -- (if there is such a node) in this match.
      , hlMatchNonEntryLabelNodes :: [NodeID]
        -- ^ The label nodes in the function graph that appears in this match
        -- but not as entries.
      , hlMatchCodeSize :: Integer
        -- ^ The size of the instruction associated with this match.
      , hlMatchLatency :: Integer
        -- ^ The latency of the instruction associated with this match.
      , hlMatchConstraints :: [Constraint]
        -- ^ The pattern-specific constraints, if any. All node IDs used in the
        -- patterns refer to nodes in the function graph (not the pattern
        -- graph). No constraint in this list may use array indices.
      , hlMatchADDUC :: Bool
        -- ^ Whether to apply the def-dom-use constraint to this match. This
        -- will typically always be set to 'True' for all matches except those
        -- of the generic phi patterns.
      , hlMatchHasControlNodes :: Bool
        -- ^ Whether the pattern contains one or more control nodes.
      , hlMatchDataNodesUsedByPhis :: [NodeID]
        -- ^ The data nodes in the function graph which are used by phi nodes
        -- appearing this match. This information is required during instruction
        -- emission in order to break cyclic data dependencies.
      , hlMatchAsmStrNodeMaplist :: [Maybe NodeID]
        -- ^ A list of mappings of the node IDs that appears in the assembly
        -- instruction template (which refer to nodes in the pattern graph) to
        -- the node IDs in the function graph which are covered by this
        -- pattern. The map list has the following appearance: each element in
        -- the list corresponds to a assembly string part with the same index in
        -- the assembly instruction template.
      }
  deriving (Show)

-- | Contains the high-level target machine parameters.
data HighLevelMachineParams
  = HighLevelMachineParams
      { hlMachineID :: TargetMachineID
        -- ^ The identifier of the target machine.
      , hlMachineRegisters :: [RegisterID]
        -- ^ The registers in the target machine.
      }
  deriving (Show)

-- | Contains a low-level CP model.
data LowLevelModel
  = LowLevelModel
      { llNumFunOpNodes :: Integer
        -- ^ The number of operation nodes appearing in the function graph.
      , llNumFunEntityNodes :: Integer
        -- ^ The number of entity nodes appearing in the function graph.
      , llNumFunLabelNodes :: Integer
        -- ^ The number of label nodes appearing in the function graph.
      , llFunEntryLabelNode :: ArrayIndex
        -- ^ The entry label node of the function graph.
      , llFunLabelDomSets :: [[ArrayIndex]]
        -- ^ The list of dominators for each label node in the function graph.
        -- An index into the outer list corresponds to the array index of a
        -- particular label node.
      , llFunLabelPostDomSets :: [[ArrayIndex]]
        -- ^ The list of postdominators for each label node in the function
        -- graph. An index into the outer list corresponds to the array index of
        -- a particular label node.
      , llFunLabelDomEdges :: [[ArrayIndex]]
        -- ^ The list of entity nodes for each label node in the function graph
        -- for which there is a dominance edge. An index into the outer list
        -- corresponds to the array index of a particular label node.
      , llFunLabelPostDomEdges :: [[ArrayIndex]]
        -- ^ The list of entity nodes for each label node in the function graph
        -- for which there is a postdominance edge. An index into the outer
        -- list corresponds to the array index of a particular label node.
      , llFunBBExecFreqs :: [ExecFreq]
        -- ^ The execution frequency of each basic block. An index into the list
        -- corresponds to the array index of a particular label node in the
        -- function graph.
      , llFunEssentialOpNodes :: [ArrayIndex]
        -- ^ Operation nodes that are essential, meaning they *must* be
        -- covered. An index into the list corresponds to the array index of a
        -- particular operation node in the function graph.
      , llFunConstraints :: [Constraint]
        -- ^ The constraints of the function graph. No constraint in this list
        -- may use IDs.
      , llNumRegisters :: Integer
        -- ^ The number of registers available in the target machine.
      , llNumMatches :: Integer
        -- ^ The number of matches.
      , llMatchOpNodesCovered :: [[ArrayIndex]]
        -- ^ The list of operation nodes in the function graph that are covered
        -- by each match. An index into the outer list corresponds to the array
        -- index of a particular match.
      , llMatchEntityNodesDefined :: [[ArrayIndex]]
        -- ^ The list of entity nodes in the function graph that are defined by
        -- each match. An index into the outer list corresponds to the array
        -- index of a particular match.
      , llMatchEntityNodesUsed :: [[ArrayIndex]]
        -- ^ The list of entity nodes in the function graph that are used by
        -- each match. An index into the outer list corresponds to the array
        -- index of a particular match.
      , llMatchEntryLabelNode :: [Maybe ArrayIndex]
        -- ^ The label node in the function graph that is the entry label (if
        -- any) of each match. An index into the list corresponds to the array
        -- index of a particular match.
      , llMatchNonEntryLabelNodes :: [[ArrayIndex]]
        -- ^ The label nodes in the function graph that are non-entry labels of
        -- each match. An index into the outer list corresponds to the array
        -- index of a particular match.
      , llMatchCodeSizes :: [Integer]
        -- ^ The code size of each match. An index into the list corresponds to
        -- the array index of a particular match.
      , llMatchLatencies :: [Integer]
        -- ^ The latency of each match. An index into the list corresponds to
        -- the array index of a particular match.
      , llMatchADDUCs :: [Bool]
        -- ^ Whether to apply the def-dom-use constraint to some match. An index
        -- into the list corresponds to the array index of a particular match.
      , llMatchConstraints :: [[Constraint]]
        -- ^ The list of constraints for each match. An index into the outer
        -- list corresponds to the array index of a particular match.
      }
  deriving (Show)

-- | Contains a solution to a high-level CP model instance.
data HighLevelSolution
  = HighLevelSolution
      { hlSolOrderOfBBs :: [NodeID]
        -- ^ The order of basic blocks (represented by the node ID of the
        -- corresponding label node).
      , hlSolSelMatches :: [MatchID]
        -- ^ The selected matchs.
      , hlSolBBAllocsForSelMatches :: [(MatchID, NodeID)]
        -- ^ The basic block (represented by the node ID of the corresponding
        -- label node) to which a particular match was allocated. A missing
        -- entry means that the corresponding match ID was not selected and thus
        -- not allocated to a valid basic block.
      , hlSolRegsOfDataNodes :: [(NodeID, RegisterID)]
        -- ^ The registers assigned for certain data nodes. A missing entry
        -- means that no register was assigned to the corresponding data node.
      , hlSolImmValuesOfDataNodes :: [(NodeID, Integer)]
        -- ^ The immediate values assigned for certain data nodes. A missing
        -- entry means that no immediate value was assigned to the corresponding
        -- data node.
      , hlSolCost :: Integer
        -- ^ The cost metric of the found solution.
      }
  deriving (Show)

-- | Contains a solution to a low-level CP model instance.
data LowLevelSolution
  = LowLevelSolution
      { llSolOrderOfBBs :: [ArrayIndex]
        -- ^ The order of basic blocks. An index into the list corresponds to
        -- the array index of the label node in the function graph which
        -- represents a particular basic block.
      , llSolIsMatchSelected :: [Bool]
        -- ^ Indicates whether a particular match was selected. An index into
        -- the list corresponds to the array index of a particular match.
      , llSolBBAllocsForMatches :: [ArrayIndex]
        -- ^ The array index of the basic block to which a particular match was
        -- allocated. An index into the list corresponds to the array index of a
        -- particular match, but this value is only valid if the corresponding
        -- value in @llIsMatchSelected@ is set to @True@.
      , llSolHasDataNodeRegister :: [Bool]
        -- ^ Indicates whether a register has been selected for a particular
        -- data node. An index into the list corresponds to the array index of a
        -- particular data node.
      , llSolRegsSelectedForDataNodes :: [ArrayIndex]
        -- ^ Specifies the register selected for a particular data node. An
        -- index into the list corresponds to the array index of a particular
        -- data node, but this value is only valid if the corresponding value in
        -- @llHasDataNodeRegister@ is set to @True@.
      , llSolHasDataNodeImmValue :: [Bool]
        -- ^ Indicates whether an immediate value has been assigned to a
        -- particular data node. An index into the list corresponds to the array
        -- index of a particular data node.
      , llSolImmValuesOfDataNodes :: [Integer]
        -- ^ Specifies the immediate value assigned to a particular data
        -- node. An index into the list corresponds to the array index of a
        -- particular data node, but this value is only valid if the
        -- corresponding value in @llHasasDataNodeImmValue@ is set to @True@.
      , llSolCost :: Integer
        -- ^ The cost metric of the found solution.
      }
  deriving (Show)

-- | Contains mappings from an array index to some ID. This is used when
-- generating the CP model instance, where we want all identifiers to be array
-- indices, which must be contiguous, instead of node IDs, match IDs, register
-- IDs, etc., which may be sparse.
data ArrayIndexMaplists
  = ArrayIndexMaplists
      { ai2OpNodeIDs :: [NodeID]
        -- ^ The list of mappings from array indices (represented as list
        -- indices) to the node IDs of operation nodes.
      , ai2EntityNodeIDs :: [NodeID]
        -- ^ The list of mappings from array indices (represented as list
        -- indices) to the node IDs of entity nodes.
      , ai2LabelNodeIDs :: [NodeID]
        -- ^ The list of mappings from array indices (represented as list
        -- indices) to the node IDs of label nodes.
      , ai2MatchIDs :: [MatchID]
        -- ^ The list of mappings from array indices (represented as list
        -- indices) to match IDs.
      , ai2RegisterIDs :: [RegisterID]
        -- ^ The list of mappings from array indices (represented as list
        -- indices) to register IDs.
      , ai2InstructionIDs :: [InstructionID]
        -- ^ The list of mappings from array indices (represented as list
        -- indices) to instruction IDs.
      }



--------------------------------
-- JSON-related class instances
--------------------------------

instance FromJSON HighLevelModel where
  parseJSON (Object v) =
    HighLevelModel
      <$> v .: "function-params"
      <*> v .: "machine-params"
      <*> v .: "match-params"
  parseJSON _ = mzero

instance ToJSON HighLevelModel where
  toJSON m =
    object [ "function-params" .= (hlFunctionParams m)
           , "machine-params"  .= (hlMachineParams m)
           , "match-params"    .= (hlMatchParams m)
           ]

instance FromJSON HighLevelFunctionParams where
  parseJSON (Object v) =
    HighLevelFunctionParams
      <$> v .: "operation-nodes"
      <*> v .: "entity-nodes"
      <*> v .: "label-nodes"
      <*> v .: "entry-label"
      <*> v .: "label-dom-sets"
      <*> v .: "label-post-dom-sets"
      <*> v .: "dom-edges"
      <*> v .: "post-dom-edges"
      <*> v .: "bb-params"
      <*> v .: "essential-op-nodes"
      <*> v .: "constraints"
  parseJSON _ = mzero

instance ToJSON HighLevelFunctionParams where
  toJSON d =
    object [ "operation-nodes"     .= (hlFunOpNodes d)
           , "entity-nodes"        .= (hlFunEntityNodes d)
           , "label-nodes"         .= (hlFunLabelNodes d)
           , "label-dom-sets"      .= (hlFunLabelDomSets d)
           , "label-post-dom-sets" .= (hlFunLabelPostDomSets d)
           , "entry-label"         .= (hlFunEntryLabelNode d)
           , "dom-edges"           .= (hlFunDomEdges d)
           , "post-dom-edges"      .= (hlFunPostDomEdges d)
           , "bb-params"           .= (hlFunBasicBlockParams d)
           , "essential-op-nodes"  .= (hlFunEssentialOpNodes d)
           , "constraints"         .= (hlFunConstraints d)
           ]

instance FromJSON HighLevelBasicBlockParams where
  parseJSON (Object v) =
    HighLevelBasicBlockParams
      <$> v .: "label"
      <*> v .: "label-node"
      <*> v .: "exec-frequency"
  parseJSON _ = mzero

instance ToJSON HighLevelBasicBlockParams where
  toJSON d =
    object [ "label"          .= (hlBBLabel d)
           , "label-node"     .= (hlBBLabelNode d)
           , "exec-frequency" .= (hlBBExecFrequency d)
           ]

instance FromJSON HighLevelMatchParams where
  parseJSON (Object v) =
    HighLevelMatchParams
      <$> v .: "instruction-id"
      <*> v .: "pattern-id"
      <*> v .: "match-id"
      <*> v .: "operation-nodes-covered"
      <*> v .: "entity-nodes-defined"
      <*> v .: "entity-nodes-used"
      <*> v .: "entry-label-node"
      <*> v .: "non-entry-label-nodes"
      <*> v .: "code-size"
      <*> v .: "latency"
      <*> v .: "constraints"
      <*> v .: "apply-def-dom-use-constraint"
      <*> v .: "has-control-nodes"
      <*> v .: "data-nodes-used-by-phis"
      <*> v .: "asm-str-node-maps"
  parseJSON _ = mzero

instance ToJSON HighLevelMatchParams where
  toJSON d =
    object [ "instruction-id"               .= (hlMatchInstructionID d)
           , "pattern-id"                   .= (hlMatchPatternID d)
           , "match-id"                     .= (hlMatchID d)
           , "operation-nodes-covered"      .= (hlMatchOpNodesCovered d)
           , "entity-nodes-defined"         .= (hlMatchEntityNodesDefined d)
           , "entity-nodes-used"            .= (hlMatchEntityNodesUsed d)
           , "entry-label-node"             .= (hlMatchEntryLabelNode d)
           , "non-entry-label-nodes"        .= (hlMatchNonEntryLabelNodes d)
           , "code-size"                    .= (hlMatchCodeSize d)
           , "latency"                      .= (hlMatchLatency d)
           , "constraints"                  .= (hlMatchConstraints d)
           , "apply-def-dom-use-constraint" .= (hlMatchADDUC d)
           , "has-control-nodes"            .= (hlMatchHasControlNodes d)
           , "data-nodes-used-by-phis"      .= (hlMatchDataNodesUsedByPhis d)
           , "asm-str-node-maps"            .= (hlMatchAsmStrNodeMaplist d)
           ]

instance FromJSON HighLevelMachineParams where
  parseJSON (Object v) =
    HighLevelMachineParams
      <$> v .: "target-machine-id"
      <*> v .: "registers"
  parseJSON _ = mzero

instance ToJSON HighLevelMachineParams where
  toJSON d =
    object [ "target-machine-id" .= (hlMachineID d)
           , "registers"         .= (hlMachineRegisters d)
           ]

instance FromJSON LowLevelModel where
  parseJSON (Object v) =
    LowLevelModel
      <$> v .: "fun-num-op-nodes"
      <*> v .: "fun-num-entity-nodes"
      <*> v .: "fun-num-label-nodes"
      <*> v .: "fun-entry-label-node"
      <*> v .: "fun-label-dom-sets"
      <*> v .: "fun-label-post-dom-sets"
      <*> v .: "fun-label-dom-edges"
      <*> v .: "fun-label-post-dom-edges"
      <*> v .: "fun-bb-exec-freqs"
      <*> v .: "fun-essential-op-nodes"
      <*> v .: "fun-constraints"
      <*> v .: "num-registers"
      <*> v .: "num-matches"
      <*> v .: "match-op-nodes-covered"
      <*> v .: "match-entity-nodes-defined"
      <*> v .: "match-entity-nodes-used"
      <*> v .: "match-entry-label-nodes"
      <*> v .: "match-non-entry-label-nodes"
      <*> v .: "match-code-sizes"
      <*> v .: "match-latencies"
      <*> v .: "match-adduc-settings"
      <*> v .: "match-constraints"
  parseJSON _ = mzero

instance ToJSON LowLevelModel where
  toJSON m =
    object [ "fun-num-op-nodes"            .= (llNumFunOpNodes m)
           , "fun-num-entity-nodes"        .= (llNumFunEntityNodes m)
           , "fun-num-label-nodes"         .= (llNumFunLabelNodes m)
           , "fun-entry-label-node"        .= (llFunEntryLabelNode m)
           , "fun-label-dom-sets"          .= (llFunLabelDomSets m)
           , "fun-label-post-dom-sets"     .= (llFunLabelPostDomSets m)
           , "fun-label-dom-edges"         .= (llFunLabelDomEdges m)
           , "fun-label-dom-post-edges"    .= (llFunLabelPostDomEdges m)
           , "fun-bb-exec-freqs"           .= (llFunBBExecFreqs m)
           , "fun-essential-op-nodes"      .= (llFunEssentialOpNodes m)
           , "fun-constraints"             .= (llFunConstraints m)
           , "num-registers"               .= (llNumRegisters m)
           , "num-matches"                 .= (llNumMatches m)
           , "match-op-nodes-covered"      .= (llMatchOpNodesCovered m)
           , "match-entity-nodes-defined"  .= (llMatchEntityNodesDefined m)
           , "match-entity-nodes-used"     .= (llMatchEntityNodesUsed m)
           , "match-entry-label-nodes"     .= (llMatchEntryLabelNode m)
           , "match-non-entry-label-nodes" .= (llMatchNonEntryLabelNodes m)
           , "match-code-sizes"            .= (llMatchCodeSizes m)
           , "match-latencies"             .= (llMatchLatencies m)
           , "match-adduc-settings"        .= (llMatchADDUCs m)
           , "match-constraints"           .= (llMatchConstraints m)
           ]

instance FromJSON HighLevelSolution where
  parseJSON (Object v) =
    HighLevelSolution
      <$> v .: "order-of-bbs"
      <*> v .: "selected-matches"
      <*> v .: "bbs-allocated-for-sel-matches"
      <*> v .: "regs-allocated-for-dnodes"
      <*> v .: "imm-values-of-dnodes"
      <*> v .: "cost"
  parseJSON _ = mzero

instance ToJSON HighLevelSolution where
  toJSON d =
    object [ "order-of-bbs"                  .= (hlSolOrderOfBBs d)
           , "selected-matches"              .= (hlSolSelMatches d)
           , "bbs-allocated-for-sel-matches" .= (hlSolBBAllocsForSelMatches d)
           , "regs-allocated-for-dnodes"     .= (hlSolRegsOfDataNodes d)
           , "imm-values-of-dnodes"          .= (hlSolImmValuesOfDataNodes d)
           , "cost"                          .= (hlSolCost d)
           ]

instance FromJSON LowLevelSolution where
  parseJSON (Object v) =
    LowLevelSolution
      <$> v .: "order-of-bbs"
      <*> v .: "is-match-selected"
      <*> v .: "bb-allocated-for-match"
      <*> v .: "has-dnode-reg"
      <*> v .: "reg-selected-for-dnode"
      <*> v .: "has-dnode-imm-value"
      <*> v .: "imm-value-of-dnode"
      <*> v .: "cost"
  parseJSON _ = mzero

instance ToJSON ArrayIndexMaplists where
  toJSON d =
    object [ "array-index-to-op-node-id-maps"     .= (ai2OpNodeIDs d)
           , "array-index-to-entity-node-id-maps" .= (ai2EntityNodeIDs d)
           , "array-index-to-label-node-id-maps"  .= (ai2LabelNodeIDs d)
           , "array-index-to-match-id-maps"       .= (ai2MatchIDs d)
           , "array-index-to-register-id-maps"    .= (ai2RegisterIDs d)
           , "array-index-to-instruction-id-maps" .= (ai2InstructionIDs d)
           ]

instance FromJSON ArrayIndexMaplists where
  parseJSON (Object v) =
    ArrayIndexMaplists
      <$> v .: "array-index-to-op-node-id-maps"
      <*> v .: "array-index-to-entity-node-id-maps"
      <*> v .: "array-index-to-label-node-id-maps"
      <*> v .: "array-index-to-match-id-maps"
      <*> v .: "array-index-to-register-id-maps"
      <*> v .: "array-index-to-instruction-id-maps"
  parseJSON _ = mzero
