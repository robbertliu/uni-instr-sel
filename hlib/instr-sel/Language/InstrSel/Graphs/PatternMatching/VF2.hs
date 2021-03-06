{-|
Copyright   :  Copyright (c) 2012-2017, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

-}

module Language.InstrSel.Graphs.PatternMatching.VF2
  ( findMatches )
where

import Language.InstrSel.Graphs.Base

import qualified Data.Set as S



-------------
-- Functions
-------------

-- | Finds all instances where a pattern graph matches within a function graph.
-- If the pattern graph is empty, then the default behavior is to indicate that
-- there are no matches.
findMatches
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Match Node]
     -- ^ Found matches.
findMatches fg pg =
  if isGraphEmpty pg
  then []
  else map toMatch $
       match fg pg []

-- | Implements the VF2 algorithm. The algorithm first finds a set of node
-- mapping candidates, and then applies a feasibility check on each of
-- them. Each candidate that passes the test is added to the existing mapping
-- state, and then the function is recursively called.
match
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ The current mapping state.
  -> [[Mapping Node]]
     -- ^ Found matches.
match fg pg st
  | length st == getNumNodes pg = [st]
  | otherwise = let cs = getCandidates fg pg st
                    good_cs = filter (checkFeasibility fg pg st) cs
                in concatMap (match fg pg) (map (:st) good_cs)

-- | Gets a set of node mapping candidates. This set consists of the pairs of
-- nodes which are successors to the nodes currently in the match set. If this
-- resultant set is empty, then the set consists of the pairs of nodes which are
-- corresponding predecessors. If this set too is empty, then the returned set
-- consists of the pairs of nodes not contained in the match set.
getCandidates
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ The current mapping state.
  -> [Mapping Node]
     -- ^ Potential candidates.
getCandidates fg pg st =
  let toMapping (fn, pn) = Mapping { fNode = fn, pNode = pn }
      m_fg = S.fromList $ map fNode st
      m_pg = S.fromList $ map pNode st
      t_out_fg = S.toList $ getTOutSet fg m_fg
      t_out_pg = S.toList $ getTOutSet pg m_pg
      t_in_fg = S.toList $ getTInSet fg m_fg
      t_in_pg = S.toList $ getTInSet pg m_pg
      t_d_fg = S.toList $ optimizePDSet $ getPDSet fg m_fg
      t_d_pg = S.toList $ optimizePDSet $ getPDSet pg m_pg
      p_out = [ (n, head t_out_pg) | n <- t_out_fg, not (null t_out_pg) ]
      p_in  = [ (n, head t_in_pg)  | n <- t_in_fg,  not (null t_in_pg)  ]
      p_d   = [ (n, head t_d_pg)   | n <- t_d_fg,   not (null t_d_pg)   ]
  in if length p_out > 0
     then map toMapping p_out
     else if length p_in > 0
          then map toMapping p_in
          else map toMapping p_d

-- | From a mapping state and a pattern node, get the corresponding function
-- node. It is assumed that there is always such a mapping.
getFNFromState :: [Mapping Node] -> Node -> Node
getFNFromState st pn =
  let fn = findFNInMapping st pn
  in if length fn == 1
     then head fn
     else if length fn == 0
          then error "getFNFromState: no mapping"
          else error "getFNFromState: multiple mappings"

-- | Checks that the node mapping is feasible by comparing their semantics and
-- syntax.
checkFeasibility
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkFeasibility fg pg st c =
  checkSemantics fg pg st c && checkSyntax fg pg st c

-- | Checks that the semantics of the matched nodes and edges are compatible.
checkSemantics
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkSemantics fg pg st c =
  let fn = fNode c
      pn = pNode c
      mapped_preds_to_pn =
        filter (`elem` (map pNode st)) (getPredecessors pg pn)
      mapped_succs_to_pn =
        filter (`elem` (map pNode st)) (getSuccessors pg pn)
  in -- Check that the nodes are of matching type
     doNodesMatch fg pg fn pn
     &&
     -- Check that the new in-edge mappings are of matching type
     all ( \pred_pn ->
           doEdgeListsMatch fg
                            pg
                            (getEdgesBetween fg (getFNFromState st pred_pn) fn)
                            (getEdgesBetween pg pred_pn pn)
         )
         mapped_preds_to_pn
     &&
     -- Check that the new out-edge mappings are of matching type
     all ( \succ_pn ->
           doEdgeListsMatch fg
                            pg
                            (getEdgesBetween fg fn (getFNFromState st succ_pn))
                            (getEdgesBetween pg pn succ_pn)
         )
         mapped_succs_to_pn
     &&
     -- Apply (any) additional checks
     customPatternMatchingSemanticsCheck fg pg st c

-- | Checks that the syntax of matched nodes are compatible (modified version of
-- equation 2 in the paper).
--
-- The modification is that the last check is removed as it appear to forbid
-- certain cases of subgraph isomorphism which we still want.
checkSyntax
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkSyntax fg pg st c =
  checkSyntaxPred fg pg st c &&
  checkSyntaxSucc fg pg st c &&
  checkSyntaxIn   fg pg st c &&
  checkSyntaxOut  fg pg st c &&
  checkSyntaxNew  fg pg st c

-- | Checks that for each predecessor of the matched pattern node that appears
-- in the current mapping state, there exists a node mapping for the
-- predecessor (modified version of equation 3 in the paper). This is a
-- consistency check.
--
-- The modification is that in this implementation I have removed the equivalent
-- check for the matched function node; I believe this to be a bug in the paper.
checkSyntaxPred
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkSyntaxPred fg pg st c =
  let m_pg = S.fromList $ map pNode st
      preds_fn = getPredSet fg (fNode c)
      preds_pn = getPredSet pg (pNode c)
      preds_pn_in_m = preds_pn `S.intersection` m_pg
  in all ( \pn -> any (\fn -> (Mapping { fNode = fn, pNode = pn }) `elem` st)
                      preds_fn
         )
         preds_pn_in_m

-- | Same as checkSyntaxPred but for the successors (modified version of
-- equation 4 in the paper).
checkSyntaxSucc
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkSyntaxSucc fg pg st c =
  let m_pg = S.fromList $ map pNode st
      succs_fn = getSuccSet fg (fNode c)
      succs_pn = getSuccSet pg (pNode c)
      succs_pn_in_m = succs_pn `S.intersection` m_pg
  in all ( \pn -> any (\fn -> (Mapping { fNode = fn, pNode = pn }) `elem` st)
                      succs_fn
         )
         succs_pn_in_m

-- | Checks that there exists a sufficient number of unmapped predecessors left
-- in the function graph to cover the unmapped predecessors left in the pattern
-- graph (equation 5 in the paper). This is a 1-look-ahead check.
checkSyntaxIn
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkSyntaxIn fg pg st c =
  let m_fg = S.fromList $ map fNode st
      m_pg = S.fromList $ map pNode st
      fn = fNode c
      pn = pNode c
      preds_fn = getPredSet fg fn
      preds_pn = getPredSet pg pn
      succs_fn = getSuccSet fg fn
      succs_pn = getSuccSet pg pn
      t_in_fg = getTInSet fg m_fg
      t_in_pg = getTInSet pg m_pg
  in ( S.size (succs_fn `S.intersection` t_in_fg)
       >=
       S.size (succs_pn `S.intersection` t_in_pg)
     )
     &&
     ( S.size (preds_fn `S.intersection` t_in_fg)
       >=
       S.size (preds_pn `S.intersection` t_in_pg)
     )

-- | Same as checkSyntaxIn but for successors (equation 6 in the paper).
checkSyntaxOut
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkSyntaxOut fg pg st c =
  let m_fg = S.fromList $ map fNode st
      m_pg = S.fromList $ map pNode st
      fn = fNode c
      pn = pNode c
      preds_fn = getPredSet fg fn
      preds_pn = getPredSet pg pn
      succs_fn = getSuccSet fg fn
      succs_pn = getSuccSet pg pn
      t_out_fg = getTOutSet fg m_fg
      t_out_pg = getTOutSet pg m_pg
  in ( S.size (succs_fn `S.intersection` t_out_fg)
       >=
       S.size (succs_pn `S.intersection` t_out_pg)
     )
     &&
     ( S.size (preds_fn `S.intersection` t_out_fg)
       >=
       S.size (preds_pn `S.intersection` t_out_pg)
     )

-- | Similar to checkSyntaxOut and checkSyntaxIn but one step further (equation
-- 7 in the paper). This is a 2-look-ahead check.
checkSyntaxNew
  :: Graph
     -- ^ The function graph.
  -> Graph
     -- ^ The pattern graph.
  -> [Mapping Node]
     -- ^ Current mapping state.
  -> Mapping Node
     -- ^ Candidate mapping.
  -> Bool
checkSyntaxNew fg pg st c =
  let m_fg = S.fromList $ map fNode st
      m_pg = S.fromList $ map pNode st
      fn = fNode c
      pn = pNode c
      preds_fn = getPredSet fg fn
      preds_pn = getPredSet pg pn
      succs_fn = getSuccSet fg fn
      succs_pn = getSuccSet pg pn
      t_in_fg = getTInSet fg m_fg
      t_in_pg = getTInSet pg m_pg
      t_out_fg = getTOutSet fg m_fg
      t_out_pg = getTOutSet pg m_pg
      t_fg = t_in_fg `S.union` t_out_fg
      t_pg = t_in_pg `S.union` t_out_pg
      neg_n_fg = (S.fromList $ getAllNodes fg) S.\\ m_fg S.\\ t_fg
      neg_n_pg = (S.fromList $ getAllNodes pg) S.\\ m_pg S.\\ t_pg
  in ( S.size (neg_n_fg `S.intersection` preds_fn)
       >=
       S.size (neg_n_pg `S.intersection` preds_pn)
     )
     &&
     ( S.size (neg_n_fg `S.intersection` succs_fn)
       >=
       S.size (neg_n_pg `S.intersection` succs_pn)
     )

-- | Gets the set of predecessor nodes for a given graph and node.
getPredSet :: Graph -> Node -> S.Set Node
getPredSet g n = S.fromList $ getPredecessors g n

-- | Gets the set of successor nodes for a given graph and node.
getSuccSet :: Graph -> Node -> S.Set Node
getSuccSet g n = S.fromList $ getSuccessors g n

-- | Gets the T_out set.
getTOutSet
  :: Graph
     -- ^ Graph in which the nodes of M belong.
  -> S.Set Node
     -- ^ The M set.
  -> S.Set Node
getTOutSet g m =
  let t_out = S.foldr (\n t -> t `S.union` getSuccSet g n) S.empty m
  in t_out S.\\ m

-- | Gets the T_in set.
getTInSet
  :: Graph
     -- ^ Graph in which the nodes of M belong.
  -> S.Set Node
     -- ^ The M set.
  -> S.Set Node
getTInSet g m =
  let t_out = S.foldr (\n t -> t `S.union` getPredSet g n) S.empty m
  in t_out S.\\ m

-- | Gets the P_D set.
getPDSet
  :: Graph
     -- ^ Graph in which the nodes of M belong.
  -> S.Set Node
     -- ^ The M set.
  -> S.Set Node
getPDSet g m = (S.fromList $ getAllNodes g) S.\\ m

-- | Returns an optimized P_D set, which only includes operation and block
-- nodes. This will result in fewer stupid candidates as these nodes are the
-- most constrained.
optimizePDSet :: S.Set Node -> S.Set Node
optimizePDSet = S.filter (\n -> isOperationNode n || isBlockNode n)
