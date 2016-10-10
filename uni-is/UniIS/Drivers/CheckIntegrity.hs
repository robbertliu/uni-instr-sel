{-|
Copyright   :  Copyright (c) 2012-2016, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

-}

module UniIS.Drivers.CheckIntegrity
  ( run )
where

import UniIS.Drivers.Base
import Language.InstrSel.Functions
  ( Function (..) )
import Language.InstrSel.Graphs
import Language.InstrSel.OpStructures
  ( OpStructure (..) )
import Language.InstrSel.OpTypes
import Language.InstrSel.PrettyShow
import Language.InstrSel.TargetMachines
  ( InstrPattern (..) )

import Language.InstrSel.Utils.IO
  ( reportErrorAndExit
  , errorExitCode
  )

import Data.List
  ( intercalate
  , nubBy
  , sort
  )



-------------
-- Functions
-------------

run
  :: CheckAction
  -> Maybe Function
  -> Maybe InstrPattern
  -> IO [Output]

run CheckFunctionIntegrity (Just fun) _ =
  do let g = osGraph $ functionOS fun
     return $ mkOutput $
              checkGraphInvariants g

run CheckPatternIntegrity _ (Just pat) =
  do let g = osGraph $ patOS pat
     return $ mkOutput $
              checkGraphInvariants g

run _ _ _ = reportErrorAndExit "CheckIntegrity: unsupported action"

-- | Makes an 'Output' from a given output log. An empty log indicates no
-- errors.
mkOutput :: [String] -> [Output]
mkOutput [] = [toOutput ""]
mkOutput msgs =
  [toOutputWithExitCode errorExitCode (intercalate "\n\n" msgs)]

checkGraphInvariants :: Graph -> [String]
checkGraphInvariants g =
  let check n =
        let msg0 = nodeCheck n
            in_edges = getInEdges g n
            msg1 = concatMap edgeNodeCheck in_edges
            msg2 = inEdgeOrderCheck n in_edges
            out_edges = getInEdges g n
            msg3 = concatMap edgeNodeCheck out_edges
            msg4 = outEdgeOrderCheck n out_edges
        in concat [msg0, msg1, msg2, msg3, msg4]
      nodeCheck n =
        case (getNodeType n) of
          (ComputationNode op) ->
            let msg0 = checkNumInDtFlowEdges  g n (numOperands op)
                msg1 = checkNumOutDtFlowEdges g n ( if producesValue op
                                                    then 1 else 0 )
                msg2 = checkNumInStFlowEdges  g n ( if requiresState op
                                                    then 1 else 0 )
                msg3 = checkNumOutStFlowEdges g n ( if requiresState op
                                                    then 1 else 0 )
                msg4 = checkNumInCtrlFlowEdges  g n 0
                msg5 = checkNumOutCtrlFlowEdges g n 0
            in concat [msg0, msg1, msg2, msg3, msg4, msg5]
          (ControlNode op) ->
            let msg0 = checkNumInDtFlowEdges  g n (numOperands op)
                msg1 = checkNumOutDtFlowEdges g n ( if producesValue op
                                                    then 1 else 0 )
                msg2 = checkNumInStFlowEdges  g n ( if requiresState op
                                                    then 1 else 0 )
                msg3 = checkNumOutStFlowEdges g n ( if requiresState op
                                                    then 1 else 0 )
                msg4 = checkNumInCtrlFlowEdges  g n (numInCtrlFlows op)
                msg5 = checkNumOutCtrlFlowEdges g n (numOutCtrlFlows op)
            in concat [msg0, msg1, msg2, msg3, msg4, msg5]
          (CallNode {}) ->
            let msg0 = checkNumInStFlowEdges  g n 1
                msg1 = checkNumOutStFlowEdges g n 1
                msg2 = checkNumInCtrlFlowEdges  g n 0
                msg3 = checkNumOutCtrlFlowEdges g n 0
            in concat [msg0, msg1, msg2, msg3]
          (ValueNode {}) ->
            let msg0 = checkNumInDtFlowEdges g n 1
                msg1 = checkNumOutDtFlowEdgesAtLeast g n 1
                msg2 = checkNumInStFlowEdges  g n 0
                msg3 = checkNumOutStFlowEdges g n 0
                msg4 = checkNumInCtrlFlowEdges  g n 0
                msg5 = checkNumOutCtrlFlowEdges g n 0
            in concat [msg0, msg1, msg2, msg3, msg4, msg5]
          (BlockNode {}) ->
            let msg0 = checkNumInDtFlowEdges  g n 0
                msg1 = checkNumOutDtFlowEdges g n 0
                msg2 = checkNumInStFlowEdges  g n 0
                msg3 = checkNumOutStFlowEdges g n 0
            in concat [msg0, msg1, msg2, msg3]
          PhiNode ->
            let msg0 = checkNumInDtFlowEdgesAtLeast g n 1
                msg1 = checkNumOutDtFlowEdges g n 1
                msg2 = checkNumInStFlowEdges  g n 0
                msg3 = checkNumOutStFlowEdges g n 0
                msg4 = checkNumInCtrlFlowEdges  g n 0
                msg5 = checkNumOutCtrlFlowEdges g n 0
            in concat [msg0, msg1, msg2, msg3, msg4, msg5]
          StateNode ->
            let msg0 = checkNumInStFlowEdges  g n 1
                msg1 = checkHasOutStFlowEdgeOrOutDefEdge g n
                msg2 = checkNumInDtFlowEdges  g n 0
                msg3 = checkNumOutDtFlowEdges g n 0
                msg4 = checkNumInCtrlFlowEdges  g n 0
                msg5 = checkNumOutCtrlFlowEdges g n 0
            in concat [msg0, msg1, msg2, msg3, msg4, msg5]
          CopyNode ->
            let msg0 = checkNumInDtFlowEdges  g n 1
                msg1 = checkNumOutDtFlowEdges g n 1
                msg2 = checkNumInStFlowEdges  g n 0
                msg3 = checkNumOutStFlowEdges g n 0
                msg4 = checkNumInCtrlFlowEdges  g n 0
                msg5 = checkNumOutCtrlFlowEdges g n 0
            in concat [msg0, msg1, msg2, msg3, msg4, msg5]
      edgeNodeCheck e =
        let src = getSourceNode g e
            trg = getTargetNode g e
            src_type = getNodeType src
            trg_type = getNodeType trg
        in case (getEdgeType e) of
            ControlFlowEdge ->
              if not (isBlockNode src || isControlNode src)
              then [ "Invalid source node type: " ++ show e ++ " has " ++
                     pShow src_type ++ ", expected either block or control node"
                   ]
              else if not (isBlockNode trg || isControlNode trg)
                   then [ "Invalid target node type: " ++ show e ++ " has " ++
                          pShow trg_type ++ ", expected either block or " ++
                          "control node"
                        ]
                   else if isBlockNode src && not (isControlNode trg)
                        then [ "Invalid target node type: " ++ show e ++
                               " has " ++ pShow trg_type ++ ", expected " ++
                               "control node"
                        ]
                        else if isControlNode src && not (isBlockNode trg)
                             then [ "Invalid target node type: " ++ show e ++
                                    " has " ++ pShow trg_type ++ ", " ++
                                    "expected block node"
                                  ]
                             else []
            DataFlowEdge ->
              if not (isOperationNode src || isBlockNode src || isValueNode src)
              then [ "Invalid source node type: " ++ show e ++ " has " ++
                     pShow src_type ++ ", expected either a computation, " ++
                     "control, call, phi, copy, block, or value node"
                   ]
              else if not (isOperationNode trg || isValueNode trg)
                   then [ "Invalid target node type: " ++ show e ++ " has " ++
                          pShow trg_type ++ ", expected either a " ++
                          "computation, control, call, phi, copy, or value node"
                        ]
                   else if isOperationNode src && not (isValueNode trg)
                        then [ "Invalid target node type: " ++ show e ++
                               " has " ++ pShow trg_type ++ ", expected " ++
                               "value node"
                        ]
                        else if isValueNode src && not (isOperationNode trg)
                             then [ "Invalid target node type: " ++ show e ++
                                    " has " ++ pShow trg_type ++ ", " ++
                                    "expected computation, control, call, " ++
                                    "phi, or copy node"
                                  ]
                             else if isBlockNode src && not (isValueNode trg)
                                  then [ "Invalid target node type: " ++
                                         show e ++ " has " ++ pShow trg_type ++
                                         ", expected value node"
                                       ]
                                  else []
            StateFlowEdge ->
              if not (isOperationNode src || isBlockNode src || isStateNode src)
              then [ "Invalid source node type: " ++ show e ++ " has " ++
                     pShow src_type ++ ", expected either a computation, " ++
                     "control, call, phi, copy, block or state node"
                   ]
              else if not (isOperationNode trg || isStateNode trg)
                   then [ "Invalid target node type: " ++ show e ++ " has " ++
                          pShow trg_type ++ ", expected either a " ++
                          "computation, control, call, phi, copy, or state node"
                        ]
                   else if isOperationNode src && not (isStateNode trg)
                        then [ "Invalid target node type: " ++ show e ++
                               " has " ++ pShow trg_type ++ ", expected " ++
                               "state node"
                        ]
                        else if isStateNode src && not (isOperationNode trg)
                             then [ "Invalid target node type: " ++ show e ++
                                    " has " ++ pShow trg_type ++ ", " ++
                                    "expected computation, control, call, " ++
                                    "phi, or copy node"
                                  ]
                             else if isBlockNode src && not (isStateNode trg)
                                  then [ "Invalid target node type: " ++
                                         show e ++ " has " ++ pShow trg_type ++
                                         ", expected state node"
                                       ]
                                  else []
            DefEdge ->
              if not (isBlockNode src || isValueNode src || isStateNode src)
              then [ "Invalid source node type: " ++ show e ++ " has " ++
                     pShow src_type ++ ", expected either block, value or " ++
                     "state node"
                   ]
              else if not ( isBlockNode src ||
                            isValueNode src ||
                            isStateNode src
                          )
                   then [ "Invalid target node type: " ++ show e ++ " has " ++
                          pShow trg_type ++ ", expected either block, value " ++
                          "or state node"
                        ]
                   else if isBlockNode src &&
                           not (isValueNode trg || isStateNode trg)
                        then [ "Invalid target node type: " ++ show e ++
                               " has " ++ pShow trg_type ++ ", expected " ++
                               "value or state node"
                        ]
                        else if isValueNode src && not (isBlockNode trg)
                             then [ "Invalid target node type: " ++ show e ++
                                    " has " ++ pShow trg_type ++ ", " ++
                                    "expected block node"
                                  ]
                             else if isStateNode src && not (isBlockNode trg)
                                  then [ "Invalid target node type: " ++
                                         show e ++ " has " ++ pShow trg_type ++
                                         ", expected block node"
                                       ]
                                  else []
      inEdgeOrderCheck n es =
        let dt_es = nubBy haveSameInEdgeNrs $
                    filter isDataFlowEdge $
                    es
            msg0 = checkNumberOrder n "inbound data-flow edges" $
                   map getInEdgeNr dt_es
            st_es = filter isStateFlowEdge es
            msg1 = checkNumberOrder n "inbound state-flow edges" $
                   map getInEdgeNr st_es
            ctrl_es = filter isControlFlowEdge es
            msg2 = checkNumberOrder n "inbound control-flow edges" $
                   map getInEdgeNr ctrl_es
            def_es = filter isDefEdge es
            msg3 = checkNumberOrder n "inbound definition edges" $
                   map getInEdgeNr def_es
        in concat [msg0, msg1, msg2, msg3]
      outEdgeOrderCheck n es =
        let dt_es = filter isDataFlowEdge es
            msg0 = checkNumberOrder n "outbound data-flow edges" $
                   map getOutEdgeNr dt_es
            st_es = filter isStateFlowEdge es
            msg1 = checkNumberOrder n "outbound state-flow edges" $
                   map getOutEdgeNr st_es
            ctrl_es = filter isControlFlowEdge es
            msg2 = checkNumberOrder n "outbound control-flow edges" $
                   map getOutEdgeNr ctrl_es
            def_es = filter isDefEdge es
            msg3 = checkNumberOrder n "outbound definition edges" $
                   map getOutEdgeNr def_es
        in concat [msg0, msg1, msg2, msg3]
      checkNumberOrder :: Node -> String -> [EdgeNr] -> [String]
      checkNumberOrder n e_type ns =
        let sorted = sort $ map fromIntegral ns
        in if length sorted /= (last sorted - 1)
           then [ "Inconsistent edge order: " ++ show n ++ " has " ++ e_type ++
                  " edges with order " ++ pShow sorted ++ ", expected a " ++
                  "contigous sequence"
                ]
           else []
  in concat $
     foldr (\n msgs -> (check n:msgs)) [] $
     getAllNodes g

numInCtrlFlows :: ControlOp -> Int
numInCtrlFlows Br = 1
numInCtrlFlows CondBr = 1
numInCtrlFlows Ret = 1

numOutCtrlFlows :: ControlOp -> Int
numOutCtrlFlows Br = 1
numOutCtrlFlows CondBr = 2
numOutCtrlFlows Ret = 0

checkNumInDtFlowEdges :: Graph -> Node -> Int -> [String]
checkNumInDtFlowEdges g n exp_num =
  let act_num = length $
                nubBy haveSameInEdgeNrs $
                getDtFlowInEdges g n
  in if act_num /= exp_num
     then [ "Wrong number of inbound data-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected " ++ show exp_num
          ]
     else []

checkNumInDtFlowEdgesAtLeast :: Graph -> Node -> Int -> [String]
checkNumInDtFlowEdgesAtLeast g n exp_num =
  let act_num = length $
                nubBy haveSameInEdgeNrs $
                getDtFlowInEdges g n
  in if act_num < exp_num
     then [ "Wrong number of inbound data-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected at least " ++ show exp_num
          ]
     else []

checkNumOutDtFlowEdges :: Graph -> Node -> Int -> [String]
checkNumOutDtFlowEdges g n exp_num =
  let act_num = length $
                nubBy haveSameOutEdgeNrs $
                getDtFlowOutEdges g n
  in if act_num /= exp_num
     then [ "Wrong number of outbound data-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected " ++ show exp_num
          ]
     else []

checkNumOutDtFlowEdgesAtLeast :: Graph -> Node -> Int -> [String]
checkNumOutDtFlowEdgesAtLeast g n exp_num =
  let act_num = length $
                nubBy haveSameOutEdgeNrs $
                getDtFlowOutEdges g n
  in if act_num < exp_num
     then [ "Wrong number of outbound data-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected at least" ++ show exp_num
          ]
     else []

checkNumInCtrlFlowEdges :: Graph -> Node -> Int -> [String]
checkNumInCtrlFlowEdges g n exp_num =
  let act_num = length $ getCtrlFlowInEdges g n
  in if act_num /= exp_num
     then [ "Wrong number of inbound control-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected " ++ show exp_num
          ]
     else []

checkNumOutCtrlFlowEdges :: Graph -> Node -> Int -> [String]
checkNumOutCtrlFlowEdges g n exp_num =
  let act_num = length $ getCtrlFlowOutEdges g n
  in if act_num /= exp_num
     then [ "Wrong number of outbound control-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected " ++ show exp_num
          ]
     else []

checkNumInStFlowEdges :: Graph -> Node -> Int -> [String]
checkNumInStFlowEdges g n exp_num =
  let act_num = length $ getStFlowInEdges g n
  in if act_num /= exp_num
     then [ "Wrong number of inbound state-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected " ++ show exp_num
          ]
     else []

checkNumOutStFlowEdges :: Graph -> Node -> Int -> [String]
checkNumOutStFlowEdges g n exp_num =
  let act_num = length $ getStFlowOutEdges g n
  in if act_num /= exp_num
     then [ "Wrong number of outbound state-flow edges: " ++ show n ++
            " has " ++ show act_num ++ ", expected " ++ show exp_num
          ]
     else []

checkHasOutStFlowEdgeOrOutDefEdge :: Graph -> Node -> [String]
checkHasOutStFlowEdgeOrOutDefEdge g n =
  let num_st_es = length $ getStFlowOutEdges g n
      num_def_es = length $ getDefOutEdges g n
  in if num_st_es /= 1 && num_def_es /= 1
     then [ "Wrong number of outbound state-flow or definition edges: " ++
            show n ++ " has " ++ show num_st_es ++ " state-flow edges and " ++
            show num_def_es ++ " definition edges, expected either " ++
            "1 state-flow edge or 1 definition edge (but not both)"
          ]
     else []
