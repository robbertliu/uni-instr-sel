{-|
Copyright   :  Copyright (c) 2012-2017, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

-}

module Language.InstrSel.OpStructures.Transformations
  ( canonicalizeCopies
  , enforcePhiNodeInvariants
  , lowerPointers
  , removeDeadCode
  , removePhiNodeRedundancies
  , removeRedundantConversions
  )
where

import Language.InstrSel.Constraints
  ( NodeExpr (..) )
import Language.InstrSel.Constraints.ConstraintBuilder
import Language.InstrSel.Constraints.ConstraintFolder
import Language.InstrSel.DataTypes
import Language.InstrSel.Graphs
import Language.InstrSel.Graphs.PatternMatching.VF2
import Language.InstrSel.OpStructures.Base
import Language.InstrSel.OpTypes
import Language.InstrSel.PrettyShow
import Language.InstrSel.Utils
  ( Natural
  , Range (..)
  , rangeFromSingleton
  , groupBy
  )

import Data.Maybe
  ( isJust
  , fromJust
  )
import Data.List
  ( intersect
  , nub
  , nubBy
  )



-------------
-- Functions
-------------

-- | Finds computations that are synonymous with a copy operation, and replaces
-- such computation nodes with 'CopyNode's.
canonicalizeCopies :: OpStructure -> OpStructure
canonicalizeCopies os =
  let mkTempValueNode =
        ValueNode { typeOfValue = AnyType
                  , originOfValue = []
                  }
      mkIntConstValueNode c_val =
        ValueNode { typeOfValue = IntConstType
                                    { intConstValue = rangeFromSingleton c_val
                                    , intConstNumBits = Nothing
                                    }
                  , originOfValue = []
                  }
      mkCompNode op = ComputationNode { compOp = CompArithOp op }
      mkPat op c_val =
        mkGraph ( map Node $
                  [ ( 0, NodeLabel 0 (mkCompNode op) )
                  , ( 1, NodeLabel 1 mkTempValueNode )
                  , ( 2, NodeLabel 2 (mkIntConstValueNode c_val) )
                  , ( 3, NodeLabel 3 mkTempValueNode )
                  ]
                )
                ( map Edge $
                  ( [ ( 0, 3, EdgeLabel DataFlowEdge 0 0 )
                    , ( 1, 0, EdgeLabel DataFlowEdge 0 0 )
                    , ( 2, 0, EdgeLabel DataFlowEdge 0 1 )
                    ]
                  )
                )
                Nothing
      cp_patterns = map (\(op, c) -> mkPat op c)
                        [ (IntOp Add,  0)
                        , (IntOp Mul,  1)
                        , (IntOp  Or,  0)
                        , (IntOp And, -1)
                        ]
      fg = osGraph os
      matches = nubBy ( \m1 m2 ->
                        let p1_ns = map pNode $ fromMatch m1
                            p2_ns = map pNode $ fromMatch m2
                            comp_pn1 = head $ filter isComputationNode p1_ns
                            comp_pn2 = head $ filter isComputationNode p2_ns
                            comp_fn1 = head $ findFNInMatch m1 comp_pn1
                            comp_fn2 = head $ findFNInMatch m2 comp_pn2
                        in comp_fn1 == comp_fn2
                      ) $
                -- If both input arguments are constants, then the same match
                -- will be found twice
                concatMap (findMatches fg) cp_patterns
      process m os' =
        let g0 = osGraph os'
            p_ns = map pNode $ fromMatch m
            comp_pn = head $ filter isComputationNode p_ns
            const_pn = head $ filter isValueNodeWithConstValue p_ns
            comp_fn = head $ findFNInMatch m comp_pn
            const_fn = head $ findFNInMatch m const_pn
            temp_fn = head $
                      filter (/= const_fn) $
                      getPredecessors g0 comp_fn
            es = getDtFlowInEdges g0 comp_fn
            g1 = foldr delEdge g0 es
            (g2, _) = addNewDtFlowEdge (temp_fn, comp_fn) g1
            g3 = updateNodeType CopyNode comp_fn g2
            g4 = if length (getEdges g3 const_fn) == 0
                 then delNode const_fn g3
                 else g3
        in os' { osGraph = g4 }
  in foldr process os matches

-- | Lowers pointer value nodes into corresponding integer values. Computation
-- nodes that operate on pointers are also either removed (if they become
-- redundant) or converted into appropriate operations.
lowerPointers
  :: Natural
     -- ^ Size (in number of bits) of a pointer value.
  -> Integer
     -- ^ Value of a null-pointer reference.
  -> Range Integer
     -- ^ Value range for pointer symbols.
  -> OpStructure
  -> OpStructure
lowerPointers ptr_size null_value ptr_sym_range os =
  transformPtrConversions $
  removeRedundantPtrConversions $
  transformPtrValueNodes ptr_size null_value ptr_sym_range os

transformPtrValueNodes
  :: Natural
  -> Integer
  -> Range Integer
  -> OpStructure
  -> OpStructure
transformPtrValueNodes ptr_size null_value ptr_sym_range os =
  let g0 = osGraph os
      new_temp_dt = IntTempType { intTempNumBits = ptr_size }
      new_null_dt = IntConstType { intConstValue = rangeFromSingleton null_value
                                 , intConstNumBits = Just ptr_size
                                 }
      new_sym_dt = IntConstType { intConstValue = ptr_sym_range
                                , intConstNumBits = Just ptr_size
                                }
      ns = filter isValueNodeWithPointerDataType $
           getAllNodes g0
      temp_ptr_ns = filter (isPointerTempType . getDataTypeOfValueNode) ns
      null_ptr_ns = filter (isPointerNullType . getDataTypeOfValueNode) ns
      sym_ptr_ns  = filter (isPointerConstType . getDataTypeOfValueNode) ns
      g1 = foldr (updateDataTypeOfValueNode new_temp_dt) g0 temp_ptr_ns
      g2 = foldr (updateDataTypeOfValueNode new_null_dt) g1 null_ptr_ns
      g3 = foldr (updateDataTypeOfValueNode new_sym_dt) g2 sym_ptr_ns
  in os { osGraph = g3 }

removeRedundantPtrConversions :: OpStructure -> OpStructure
removeRedundantPtrConversions os0 =
  let g0 = osGraph os0
      ns = filter ( \n -> let op = getOpOfComputationNode n
                          in isCompTypeConvOp op || isCompTypeCastOp op
                  ) $
           filter isComputationNode $
           getAllNodes g0
      ps = map ( \n -> ( n
                       , head $ getPredecessors g0 n
                       , head $ getSuccessors g0 n
                       )
               )
               ns
      redundant_ps = filter ( \(_, v1, v2) ->
                              let d1 = getDataTypeOfValueNode v1
                                  d2 = getDataTypeOfValueNode v2
                              in d1 `hasSameBitWidth` d2
                            )
                            ps
      g1 = foldr (\(o, _, _) g -> delNode o g) g0 redundant_ps
      os1 = os0 { osGraph = g1 }
      os2 = foldr ( \(_, in_v, out_v) os ->
                    let g = osGraph os
                        g' = mergeNodes in_v out_v g
                        os' = os { osGraph = g' }
                        os'' = replaceNodeIDInOS (getNodeID out_v)
                                                 (getNodeID in_v)
                                                 os'
                    in os''
                  )
                  os1
                  redundant_ps
  in os2

transformPtrConversions :: OpStructure -> OpStructure
transformPtrConversions os =
  let g = osGraph os
      ns = filter ( \n -> let op = getOpOfComputationNode n
                          in if isCompTypeConvOp op
                             then let (CompTypeConvOp op') = op
                                  in op' `elem` [IntToPtr, PtrToInt]
                             else False
                  ) $
           filter isComputationNode $
           getAllNodes g
      getBitWidthFromNode n = getTypeBitWidth $ getDataTypeOfValueNode n
      ps = map ( \n -> let v1 = head $ getPredecessors g n
                           v2 = head $ getSuccessors g n
                           w1 = getBitWidthFromNode v1
                           w2 = getBitWidthFromNode v2
                       in if isJust w1
                          then if isJust w2
                               then (n, fromJust w1, fromJust w2)
                               else error $ "transformPtrConversions:" ++
                                            " data type of node has no bit " ++
                                            "width: " ++ show v2
                          else error $ "transformPtrConversions:" ++
                                       " data type of node has no bit " ++
                                       "width: " ++ show v1
               )
               ns
  in foldr ( \(n, w1, w2) os' ->
             let g0 = osGraph os'
                 g1 = if w1 < w2
                      then updateOpOfComputationNode (CompTypeConvOp ZExt) n g0
                      else updateOpOfComputationNode (CompTypeConvOp Trunc) n g0
             in os' { osGraph = g1 }
           )
           os
           ps

-- | Fixes phi nodes in a given 'OpStructure' that do not abide by the graph
-- invariants:
--    - Phi nodes with multiple data-flow edges to the same value node are
--      transformed such that only one data-flow edge is kept. Concerned
--      definition edges are also replaced with a single definition edge to the
--      last block that dominates the blocks of the replaced definition edges.
--    - Phi nodes with multiple values that originate from the same block are
--      transformed such that only a single value is kept.
enforcePhiNodeInvariants :: OpStructure -> OpStructure
enforcePhiNodeInvariants = ensureSingleBlockUseInPhis .
                           ensureSingleValueUseInPhis

ensureSingleValueUseInPhis :: OpStructure -> OpStructure
ensureSingleValueUseInPhis os =
  let g = osGraph os
      entry = let n = entryBlockNode g
              in if isJust n
                 then fromJust n
                 else error $ "ensureSingleValueUseInPhis: graph has no " ++
                              "entry block"
      cfg = extractCFG g
      ns = filter ( \n ->
                    let es = getDtFlowInEdges g n
                        vs = nub $
                             map (getSourceNode g) $
                             es
                    in length es /= length vs
                  ) $
           filter isPhiNode $
           getAllNodes g
      transform phi_n g0 =
        let dt_es = getDtFlowInEdges g0 phi_n
            def_es = map (getDefEdgeOfDtOutEdge g0) dt_es
            vb_ps = map ( \(dt_e, def_e) ->
                          (getSourceNode g0 dt_e, getTargetNode g0 def_e)
                        ) $
                    zip dt_es def_es
            grouped_vb_ps = groupBy (\(v1, _) (v2, _) -> v1 == v2) vb_ps
            new_vb_ps = map ( \ps ->
                                if length ps == 1
                                then head ps
                                else ( fst $ head ps
                                     , getDomOf cfg entry $ map snd ps
                                     )
                              ) $
                          grouped_vb_ps
            g1 = foldr delEdge g0 dt_es
            g2 = foldr delEdge g1 def_es
            g3 = foldr ( \(v, b) g' ->
                         let (g'', dt_e) = addNewDtFlowEdge (v, phi_n) g'
                             out_nr = getEdgeOutNr dt_e
                             (g''', def_e) = addNewDefEdge (v, b) g''
                             g'''' = fst $ updateEdgeOutNr out_nr def_e g'''
                         in g''''
                       )
                       g2
                       new_vb_ps
        in g3
  in os { osGraph = foldr transform g ns }

ensureSingleBlockUseInPhis :: OpStructure -> OpStructure
ensureSingleBlockUseInPhis os =
  let g = osGraph os
      transformPhi phi_n g0 =
        let dt_es = getDtFlowInEdges g0 phi_n
            def_es = map (getDefEdgeOfDtOutEdge g0) dt_es
            dt_def_ps = zip dt_es def_es
            grouped_ps = groupBy ( \(_, e1) (_, e2) ->
                                   getTargetNode g0 e1 == getTargetNode g0 e2
                                 )
                                 dt_def_ps
            edges_to_remove = concatMap (\ps -> map fst ps ++ map snd ps) $
                              map tail $
                              grouped_ps
            g1 = foldr delEdge g0 edges_to_remove
        in g1
      phi_ns = filter isPhiNode $
               getAllNodes g
  in os { osGraph = foldr transformPhi g phi_ns }

-- | From a given control-flow graph and list of block nodes, gets the block
-- that is the closest dominator of all given blocks.
getDomOf
  :: Graph
  -> Node
     -- ^ The root (entry) block of the given control-flow graph.
  -> [Node]
  -> Node
getDomOf g root bs =
  let domsets = computeDomSets g root
      bs_domsets = filter (\d -> (domNode d) `elem` bs) domsets
      cs = foldr intersect (domSet $ head bs_domsets) $
           map domSet bs_domsets
      cs_domsets = filter (\d -> (domNode d) `elem` cs) domsets
      closest_dom = domNode $
                    head $
                    filter ( \d ->
                             let n = domNode d
                             in all (\d' -> n `notElem` domSet d') $
                                filter (\d' -> domNode d' /= n) $
                                cs_domsets
                           ) $
                    cs_domsets
  in closest_dom

-- | Replaces copies of the same value that act as input to a phi node with a
-- single value, and removes phi nodes that takes only one value.
removePhiNodeRedundancies :: OpStructure -> OpStructure
removePhiNodeRedundancies = ensureSingleBlockUseInPhis .
                            removeSingleValuePhiNodes

removeSingleValuePhiNodes :: OpStructure -> OpStructure
removeSingleValuePhiNodes os =
  let g = osGraph os
      ns = filter (\n -> length (getDtFlowInEdges g n) == 1) $
           filter isPhiNode $
           getAllNodes g
      remove phi_n os0 =
        let g0 = osGraph os0
            in_e = head $ getInEdges g0 phi_n
            out_e = head $ getOutEdges g0 phi_n
            in_v = getSourceNode g0 in_e
            out_v = getTargetNode g0 out_e
            in_v_def = head $
                       filter (\e -> getEdgeOutNr e == getEdgeOutNr in_e) $
                       getDefOutEdges g0 in_v
            out_v_def = head $
                        filter (\e -> getEdgeInNr e == getEdgeInNr out_e) $
                        getDefInEdges g0 out_v
            g1 = delNode phi_n g0
            g2 = delEdge in_v_def g1
            g3 = delEdge out_v_def g2
            g4 = mergeNodes in_v out_v g3
            os1 = os0 { osGraph = g4 }
            os2 = replaceNodeIDInOS (getNodeID out_v) (getNodeID in_v) os1
        in os2
  in foldr remove os ns

replaceNodeIDInOS
  :: NodeID
     -- ^ Node ID to replace.
  -> NodeID
     -- ^ Node ID to replace with.
  -> OpStructure
  -> OpStructure
replaceNodeIDInOS old_n new_n os =
  let old_valid_locs = osValidLocations os
      new_valid_locs = map ( \p@(n, locs) ->
                             if n == old_n then (new_n, locs) else p
                           )
                           old_valid_locs
      old_same_locs = osSameLocations os
      new_same_locs = map ( \p@(n1, n2) ->
                            if n1 == old_n
                            then (new_n, n2)
                            else if n2 == old_n
                                 then (n1, new_n)
                                 else p
                          )
                          old_same_locs
      old_cs = osConstraints os
      new_cs = map (replaceNodeID old_n new_n) old_cs
  in os { osValidLocations = new_valid_locs
        , osSameLocations = new_same_locs
        , osConstraints = new_cs
        }

getDefEdgeOfDtOutEdge :: Graph -> Edge -> Edge
getDefEdgeOfDtOutEdge g e =
  let es = findDefEdgeOfDtOutEdge g e
  in if length es == 1
     then head es
     else if length es == 0
          then error $ "getDefEdgeOfDtOutEdge: " ++ pShow e ++ " has no " ++
               "matching definition edge"
          else error $ "getDefEdgeOfDtOutEdge: " ++ pShow e ++ " has " ++
               "multiple matching definition edges"

-- | Removes operation and value nodes whose result are not observable.
removeDeadCode :: OpStructure -> OpStructure
removeDeadCode os0 =
  let (os1, p) = removeDeadCode' os0
      os2 = if p
            then removeDeadCode os1
            else os1
  in os2

removeDeadCode' :: OpStructure -> (OpStructure, Bool)
removeDeadCode' os0 =
  let g0 = osGraph os0
      unused = filter ( \n ->
                        let preds = map (getSourceNode g0) $
                                    getDtFlowInEdges g0 n
                            succs = map (getTargetNode g0) $
                                    getDtFlowOutEdges g0 n
                         in length succs == 0 &&
                            not (isCallNode $ head preds) &&
                            not (isIndirCallNode $ head preds)
                      ) $
               filter isValueNode $
               getAllNodes g0
  in if length unused > 0
     then let v_n = head unused
              g1 = removeDefOfValueNode v_n g0
              os1 = os0 { osGraph = g1 }
              os2 = removeValueFromLocsAndCons (getNodeID v_n) os1
          in (os2, True)
     else (os0, False)

removeDefOfValueNode :: Node -> Graph -> Graph
removeDefOfValueNode v_n g0 =
  let pred_n = let ns = map (getSourceNode g0) $
                        getDtFlowInEdges g0 v_n
               in if length ns == 1
                  then head ns
                  else error $ "removeDefOfValue: value node " ++
                               pShow v_n ++ " has unexpected " ++
                               "number of inbound data-flow edges"
      g1 = delNode v_n g0
      g2 = if isOperationNode pred_n
           then removeOpNode pred_n g1
           else g1
  in g2

removeOpNode :: Node -> Graph -> Graph
removeOpNode op_n g0 =
  let op_in_es = getDtFlowInEdges g0 op_n
      g1 = delNode op_n g0
      g2 = foldr ( \e g ->
                   let v_n = getSourceNode g1 e
                       v_out_es = getDefOutEdges g1 v_n
                   in foldr delEdge g $
                      filter (\e' -> getEdgeOutNr e' == getEdgeOutNr e) $
                      v_out_es
                 )
                 g1
                 op_in_es
  in g2

removeValueFromLocsAndCons :: NodeID -> OpStructure -> OpStructure
removeValueFromLocsAndCons v_nid os =
  let valid_locs = osValidLocations os
      new_valid_locs = filter (\(n, _) -> n /= v_nid) valid_locs
      same_locs = osSameLocations os
      new_same_locs = filter (\(n1, n2) -> n1 /= v_nid && n2 /= v_nid)
                             same_locs
      cs = osConstraints os
      new_cs = let def_f = mkDefaultFolder True (&&)
                   foldNodeExpr _ (ANodeIDExpr n) =
                     n /= v_nid
                   foldNodeExpr f expr =
                     (foldNodeExprF def_f) f expr
                   new_f = def_f { foldNodeExprF = foldNodeExpr }
               in filter (apply new_f) cs
      new_os = os { osValidLocations = new_valid_locs
                  , osSameLocations = new_same_locs
                  , osConstraints = new_cs
                  }
  in new_os

-- | Removes conversion operations that are redundant. Such a conversion is
-- redundant if its result is immediately masked to leave the same bits as
-- before the conversion.
removeRedundantConversions :: OpStructure -> OpStructure
removeRedundantConversions os =
  let g0 = osGraph os
      convs = filter (isCompTypeConvOp . getOpOfComputationNode) $
              filter isComputationNode $
              getAllNodes g0
      transform n g1 =
        let arg_n = head $ getPredecessors g1 n
            arg_n_t = getDataTypeOfValueNode arg_n
            bits = intTempNumBits arg_n_t
            uses_of_arg_n = getPredecessors g1 arg_n
            (CompTypeConvOp op) = getOpOfComputationNode n
            value = head $ getSuccessors g1 n
            uses = getSuccessors g1 value
            (use, use_v1) = -- Skip over any copy node encountered
                            if isCopyNode (head uses)
                            then let v = head $
                                         getSuccessors g1 $
                                         head uses
                                     u = head $
                                         getSuccessors g1 v
                                 in (u, v)
                            else (head uses, value)
            use_op = getOpOfComputationNode use
            (CompArithOp ar_op) = use_op
            arith_op = getArithOpType ar_op
            use_v2 = -- Skip over any copy node encountered
                     let v = head $
                             filter (/= use_v1) $
                             getPredecessors g1 use
                         v_pred = getSourceNode g1 $
                                  head $
                                  getDtFlowInEdges g1 v
                     in if isCopyNode v_pred
                        then head $ getPredecessors g1 v_pred
                        else v
            use_v2_t = getDataTypeOfValueNode use_v2
            imm = lowerBound $ intConstValue use_v2_t
        in if length uses_of_arg_n < 2 &&
              isIntTempType arg_n_t &&
              op `elem` [ZExt, SExt] &&
              length uses == 1 &&
              isComputationNode use &&
              isCompArithOp use_op &&
              arith_op `elem` [XOr, And] &&
              isValueNodeWithConstValue use_v2 &&
              ( ( bits ==  8 && imm == 255 ) ||
                ( bits == 16 && imm == 65535 )
              )
           then let old_l = getNodeLabel n
                    new_l = old_l { nodeType = CopyNode }
                    g2 = updateNodeLabel new_l n g1
                in g2
           else g1
  in os { osGraph = foldr transform g0 convs }
