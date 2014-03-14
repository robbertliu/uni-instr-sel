--------------------------------------------------------------------------------
-- |
-- Module      :  Language.InstructionSelection.CPModel.ParamMaker
-- Copyright   :  (c) Gabriel Hjort Blindell 2013
-- License     :  BSD-style (see the LICENSE file)
--
-- Maintainer  :  ghb@kth.se
-- Stability   :  experimental
-- Portability :  portable
--
-- Constructs the parameters which are used to create the CP model. These
-- include the function data, such as the IDs of the various nodes, and the
-- pattern data, which also contain the matchsets.
--
--------------------------------------------------------------------------------

module Language.InstructionSelection.CPModel.ParamMaker (
  mkParams
) where

import Language.InstructionSelection.CPModel.Base
import Language.InstructionSelection.Graphs
import Language.InstructionSelection.OpStructures
import Language.InstructionSelection.Patterns ( InstProperties (..)
                                              , PatternId
                                              )
import Language.InstructionSelection.Utils (removeDuplicates)



-------------
-- Functions
-------------

mkParams :: OpStructure -- ^ Function data.
            -> [( OpStructure
                , [(NodeMatchset, MatchsetId)]
                )] -- ^ Pattern instance data.
            -> [(InstProperties, [MatchsetId])] -- ^ Instruction data.
            -> CPModelParams
mkParams func pats insts =
  CPModelParams (mkFunctionGraphData func)
                (concatMap mkPatternInstanceData pats)
                (map mkInstructionData insts)
                -- TODO: fix building of machine data
                MachineData

mkFunctionGraphData :: OpStructure -> FunctionGraphData
mkFunctionGraphData os =
  let g = osGraph os
  in FunctionGraphData (getUniqueNodeIdsByType g isActionNode)
                       (getUniqueNodeIdsByType g isEntityNode)
                       (getUniqueNodeIdsByType g isLabelNode)
                       (computeLabelDoms g)
                       (osConstraints os)

mkPatternInstanceData :: ( OpStructure
                         , [(NodeMatchset, MatchsetId)]
                         )
                      -> [PatternInstanceData]
mkPatternInstanceData (os, matchsets) =
  let g = osGraph os
      action_ns = (getUniqueNodeIdsByType g isActionNode)
      entity_ns = (getUniqueNodeIdsByType g isActionNode)

      (node_matchsets, matchset_ids) = unzip matchsets
      id_matchsets = map convertMatchsetNToId node_matchsets
  -- TODO: implement
  in [PatternInstanceData 0
                          []
                          []
                          []
                          []
                          -- TODO: convert node IDs in constraints
                          (osConstraints os)]

mkInstructionData :: (InstProperties, [MatchsetId]) -> InstructionData
mkInstructionData (props, matchsets) = InstructionData props matchsets

-- TODO: remove
--mkUseDefs g f =
--  let nodes = filter f (allNodes g)
--      use_nodes = filter (\n -> length (successors g n) > 0) nodes
--      def_nodes = filter (\n -> length (predecessors g n) > 0) nodes
--  in UseDefNodes (map nodeId use_nodes) (map nodeId def_nodes)

-- | Deletes a node from the graph, and redirects any edges involving the given
-- node such that all outbound edges will become outbound edges of the node's
-- parent. It is assumed the graph has at most one predecessor of the node to
-- remove (if there are more than one predecessor then the edges will be
-- redirected to one of them, but it is undefined which).

delNodeKeepEdges :: Graph -> Node -> Graph
delNodeKeepEdges g n =
  let preds = predecessors g n
  in if length preds > 0
        then mergeNodes (head preds) n g
        else delNode n g

getUniqueNodeIdsByType :: Graph -> (Node -> Bool) -> [NodeId]
getUniqueNodeIdsByType g f =
  removeDuplicates $ map (nodeId) $ filter (f) $ allNodes g

-- | Computes the dominator sets concerning only the label nodes. It is assumed
-- there exists a single label which acts as the root, which is the label node
-- with no predecessors. It is also assumed that every other label node can be
-- reached from the root.

computeLabelDoms g =
  let nodes_to_remove = filter (\n -> not (isLabelNode n || isControlNode n))
                        $ allNodes g
      cfg_with_ctrl_nodes = foldl (flip delNode) g nodes_to_remove
      cfg = foldl delNodeKeepEdges
                  cfg_with_ctrl_nodes
                  (filter isControlNode $ allNodes cfg_with_ctrl_nodes)
      root = head $ filter (\n -> length (predecessors g n) == 0) (allNodes cfg)
      node_domsets = dom cfg root
      node_id_domsets = map (\(n, ns) -> (nodeId n, map nodeId ns)) node_domsets
  in node_id_domsets
