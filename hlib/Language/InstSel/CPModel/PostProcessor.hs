--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstSel.CPModel.PostProcessor
-- Copyright   : (c) Gabriel Hjort Blindell 2013-2014
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Performs the post-processing of the CP solution and post-processing
-- parameters.
--
--------------------------------------------------------------------------------

module Language.InstSel.CPModel.PostProcessor
  ( ControlDataFlowDAG
  , emitInstructions
  , mkControlDataFlowDAG
  )
where

import Language.InstSel.CPModel.Base
import Language.InstSel.Graphs
  ( MatchID
  , NodeID
  )
import Language.InstSel.TargetMachine
  hiding
  ( patAssIDMaps )
import qualified Data.Graph.Inductive as I
import Data.Maybe



--------------
-- Data types
--------------

-- | A data type representing a DAG where the nodes represent matches, and the
-- directed edges represent control and data dependencies between the
-- matches. Each edge represents either the data flowing from one pattern to
-- another, or that there is a state or control dependency between the two.
newtype ControlDataFlowDAG =
  ControlDataFlowDAG { getIntDag :: IControlDataFlowDAG }

-- | Type synonym for the internal graph.
type IControlDataFlowDAG = I.Gr MatchID ()



-------------
-- Functions
-------------

-- | Takes a CP solution data set and a list of match IDs, and produces a
-- control and data dependency DAG such that every match ID is represented by a
-- node, and there is a directed edge between two nodes if the match indicated
-- by the target node uses data produced by the match indicated by the source
-- node, or if the destination node represents a pattern with control
-- nodes. Cyclic data dependencies are broken such that the pattern containing
-- the phi node which makes use of the data appears at the top of the
-- DAG. Cyclic control dependencies will appear if there is more than one match
-- with control nodes in the list.
mkControlDataFlowDAG ::
     CPSolutionData
  -> [MatchID]
  -> ControlDataFlowDAG
mkControlDataFlowDAG cp_data is =
  let g0 = I.mkGraph (zip [0..] is) []
      g1 = foldr (addUseEdgesToDAG cp_data) g0 is
      g2 = foldr (addControlEdgesToDAG cp_data) g1 is
  in ControlDataFlowDAG g2

-- | Adds an edge for each use of data or state of the given match ID. If the
-- source node is not present in the graph, no edge is added. It is assumed that
-- there always exists exactly one node in the graph representing the match ID
-- given as argument to the function. Note that this may lead to cycles, which
-- will have to be broken as a second step.
addUseEdgesToDAG ::
     CPSolutionData
  -> MatchID
  -> IControlDataFlowDAG
  -> IControlDataFlowDAG
addUseEdgesToDAG cp_data mid g0 =
  let ds = matchData $ modelParams cp_data
      pi_n = fromJust $ getNodeOfMatch g0 mid
      pi_data = getMatchData ds mid
      ns = I.labNodes g0
      d_uses_of_pi = filter
                       (`notElem` mDataNodesUsedByPhis pi_data)
                       (mDataNodesUsed pi_data)
      s_uses_of_pi = mStateNodesUsed pi_data
      ns_d_defs =
        map (\(n, i) -> (n, mDataNodesDefined $ getMatchData ds i)) ns
      ns_s_defs =
        map (\(n, i) -> (n, mStateNodesDefined $ getMatchData ds i)) ns
      g1 = foldr (addUseEdgesToDAG' pi_n ns_d_defs) g0 d_uses_of_pi
      g2 = foldr (addUseEdgesToDAG' pi_n ns_s_defs) g1 s_uses_of_pi
  in g2

addUseEdgesToDAG' ::
     I.Node
  -> [(I.Node, [NodeID])]
     -- ^ List of defs.
  -> NodeID
     -- ^ A use.
  -> IControlDataFlowDAG
  -> IControlDataFlowDAG
addUseEdgesToDAG' n def_maps use g =
  let ns = map fst $ filter (\m -> use `elem` snd m) def_maps
  in foldr (\n' g' -> I.insEdge (n', n, ()) g') g ns

-- | If the given match ID represents a pattern with control nodes,
-- then an edge will be added to the node of that match ID from every
-- other node.
addControlEdgesToDAG ::
     CPSolutionData
  -> MatchID
  -> IControlDataFlowDAG
  -> IControlDataFlowDAG
addControlEdgesToDAG cp_data mid g =
  let pi_data = getMatchData (matchData $ modelParams cp_data) mid
  in if mHasControlNodes pi_data
     then let ns = I.labNodes g
              pi_n = fst $ head $ filter (\(_, i) -> i == mid) ns
              other_ns = map fst $ filter (\(_, i) -> i /= mid) ns
          in foldr (\n' g' -> I.insEdge (n', pi_n, ()) g') g other_ns
     else g

-- | Gets the internal node ID (if any) of the node with a given match ID as its
-- label. It is assumed that there is always at most one such node in the graph.
getNodeOfMatch :: IControlDataFlowDAG -> MatchID -> Maybe I.Node
getNodeOfMatch g mid =
  let ns = filter (\n -> snd n == mid) $ I.labNodes g
  in if length ns > 0
     then Just (fst $ head ns)
     else Nothing

-- | Retrieves the 'MatchData' entity with matching match
-- ID. It is assumed that exactly one such entity always exists in the given
-- list.
getMatchData :: [MatchData] -> MatchID -> MatchData
getMatchData ps piid = fromJust $ findMatchData ps piid

-- | Retrieves the 'Instruction' entity with matching instruction ID. It is
-- assumed that such an entity always exists in the given list.
getInst :: [Instruction] -> InstructionID -> Instruction
getInst is iid = fromJust $ findInstruction is iid

-- | Emits a list of assembly instructions for a given 'ControlDataFlowDAG'.
emitInstructions ::
     CPSolutionData
  -> TargetMachine
  -> ControlDataFlowDAG
  -> [String]
emitInstructions cp m dag =
  let sorted_pis = I.topsort' (getIntDag dag)
  in filter (\i -> length i > 0) $ map (emitInstruction cp m) sorted_pis

-- | Emits the corresponding instruction of a given match ID.
emitInstruction ::
     CPSolutionData
  -> TargetMachine
  -> MatchID
  -> String
emitInstruction cp m piid =
  let pi_data = getMatchData (matchData $ modelParams cp) piid
      i_data = getInst (tmInstructions m) (mInstructionID pi_data)
      inst_ass_parts = instAssemblyStr i_data
  in concatMap (produceInstPart cp m pi_data) (assStrParts inst_ass_parts)

getNIDFromAID :: MatchData -> AssemblyID -> NodeID
getNIDFromAID md aid = (mAssIDMaps md) !! (fromIntegral aid)

lookupBBLabel :: NodeID -> [BBLabelData] -> Maybe BBLabelID
lookupBBLabel n ds =
  let found = filter (\d -> labNode d == n) ds
  in if length found > 0
     then Just $ labBB $ head found
     else Nothing

produceInstPart ::
     CPSolutionData
  -> TargetMachine
  -> MatchData
  -> AssemblyPart
  -> String
produceInstPart _ _ _ (AssemblyVerbatim s) = s
produceInstPart cp _ md (AssemblyImmValue aid) =
  let n = getNIDFromAID md aid
      imm = lookup n $ immValuesOfDataNodes cp
      prefix = "#"
  in if isJust imm
     then prefix ++ (show $ fromJust imm)
     else prefix ++ "?"
produceInstPart cp m md (AssemblyRegister aid) =
  let n = getNIDFromAID md aid
      reg = lookup n $ regsOfDataNodes cp
  in if isJust reg
     then let regsym = fromJust $ lookup (fromJust reg) (tmRegisters m)
          in show regsym
     else "?"
produceInstPart cp _ md (AssemblyBBLabel aid) =
  let n = getNIDFromAID md aid
      lab = lookupBBLabel n $ funcBBLabels $ functionData $ modelParams cp
  in if isJust lab
     then show $ fromJust lab
     else "?"
