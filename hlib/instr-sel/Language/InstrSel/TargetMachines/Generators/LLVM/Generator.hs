{-|
Copyright   :  Copyright (c) 2012-2016, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

-}

module Language.InstrSel.TargetMachines.Generators.LLVM.Generator
  ( generateTargetMachine )
where

import qualified Language.InstrSel.DataTypes as D
import Language.InstrSel.Graphs
import Language.InstrSel.OpStructures.Base
import Language.InstrSel.OpStructures.LLVM.OSMaker
import qualified Language.InstrSel.TargetMachines.Base as TM
import Language.InstrSel.TargetMachines.Generators.GenericInstructions
import qualified Language.InstrSel.TargetMachines.Generators.LLVM.Base as LLVM
import Language.InstrSel.TargetMachines.IDs
import Language.InstrSel.Functions.IDs
import Language.InstrSel.Utils
  ( capitalize
  , splitOn
  , splitStartingOn
  , isNumeric
  )

import qualified LLVM.General.AST as LLVM
  ( Module (..)
  , Definition (..)
  )
import qualified LLVM.General.AST.Global as LLVM
  ( Global (..) )
import qualified LLVM.General.AST.Name as LLVM

import Control.Monad
  ( foldM )

import Data.Maybe
  ( isJust
  , fromJust
  , mapMaybe
  , catMaybes
  )

import Data.List
  ( intersperse )



-------------
-- Functions
-------------

generateTargetMachine
  :: LLVM.MachineDescription
  -> Either String TM.TargetMachine
     -- ^ An error message or the generated target machine.
generateTargetMachine m =
  do let mkPhiInstrEmitTemplate arg_ids ret_id =
           ( TM.EmitStringTemplate
             $ [ [ TM.ESLocationOfValueNode ret_id
                 , TM.ESVerbatim " = PHI "
                 ]
                 ++ ( concat
                      $ intersperse
                          [TM.ESVerbatim " "]
                          ( map ( \n ->
                                  [ TM.ESVerbatim "("
                                  , TM.ESLocationOfValueNode n
                                  , TM.ESVerbatim ", "
                                  , TM.ESBlockOfValueNode n
                                  , TM.ESVerbatim ")"
                                  ]
                                )
                                arg_ids
                          )
                    )
               ]
           )
         locs = mkLocations m
         generic_instrs = [mkPhiInstruction mkPhiInstrEmitTemplate]
                          ++ [mkBrFallThroughInstruction]
                          ++ [mkDataDefInstruction]
                          ++ [mkTempNullCopyInstruction [1, 8, 16, 32]]
                          ++ [mkInactiveInstruction]
     instrs <- mkInstructions m locs
     let all_instrs = instrs
                      ++
                      reassignInstrIDs (toInstructionID $ length instrs)
                                       generic_instrs
     return TM.TargetMachine
              { TM.tmID = toTargetMachineID $ capitalize $ LLVM.mdID m
              , TM.tmInstructions = all_instrs
              , TM.tmLocations = locs
              }

mkLocations :: LLVM.MachineDescription -> [TM.Location]
mkLocations m =
  map processLoc $ zip ([0..] :: [Integer]) (LLVM.mdLocations m)
  where processLoc (loc_id, LLVM.RegLocation name value) =
          TM.Location { TM.locID = toLocationID loc_id
                      , TM.locName = TM.toLocationName name
                      , TM.locValue = value
                      }

mkInstructions
  :: LLVM.MachineDescription
  -> [TM.Location]
  -> Either String [TM.Instruction]
     -- ^ An error message or the generated instructions.
mkInstructions m locs =
  mapM processInstr $ zip ([0..] :: [Integer]) (LLVM.mdInstructions m)
  where processInstr (i_id, i) =
          do let instr_id = TM.toInstructionID i_id
                 props = mkInstrProps i
             patterns <- mkInstrPatterns locs i
             return TM.Instruction { TM.instrID = instr_id
                                   , TM.instrPatterns = patterns
                                   , TM.instrProps = props
                                   }

mkInstrPatterns
  :: [TM.Location]
  -> LLVM.Instruction
  -> Either String [TM.InstrPattern]
     -- ^ An error message or the generated instruction patterns.
mkInstrPatterns locs i =
  mapM processInstrPattern $ zip ([0..] :: [Integer]) (LLVM.instrPatterns i)
  where processInstrPattern (p_num, p) =
          processSemantics p_num (LLVM.instrSemantics p) (LLVM.instrOperands p)
        processSemantics p_num p ops =
          do let p_id = TM.toPatternID p_num
             os0 <-mkOpStructure p
             os1 <- addOperandConstraints ops locs os0
             ext_value_nodes <- mapM (findValueNodeFromOperand os1) ops
             let ext_value_ids = map getNodeID $ catMaybes ext_value_nodes
             tmpl <- mkEmitString i os1 (LLVM.instrEmitString i)
             return TM.InstrPattern { TM.patID = p_id
                                    , TM.patOS = os1
                                    , TM.patExternalData = ext_value_ids
                                    , TM.patEmitString = tmpl
                                    }
        findValueNodeFromOperand os' (LLVM.RegInstrOperand op_name _) =
          do n <- findValueNode os' op_name
             if isJust n
             then return n
             else Left $ "mkInstrPatterns: no value node with origin "
                         ++ "'" ++ op_name ++ "''"
        findValueNodeFromOperand os' (LLVM.ImmInstrOperand op_name _) =
          do n <- findValueNode os' op_name
             if isJust n
             then return n
             else Left $ "mkInstrPatterns: no value node with origin "
                         ++ "'" ++ op_name ++ "''"
        findValueNodeFromOperand os' (LLVM.AbsAddrInstrOperand op_name _) =
          findValueNode os' op_name
        findValueNodeFromOperand os' (LLVM.RelAddrInstrOperand op_name _) =
          findValueNode os' op_name
        findValueNode os' origin =
          let n = findValueNodesWithOrigin (osGraph os') origin
          in if length n == 1
             then return $ Just $ head n
             else if length n > 0
                  then Left $ "mkInstrPatterns: multiple value nodes with "
                              ++ "origin '" ++ origin ++ "'"
                  else return Nothing

addOperandConstraints
  :: [LLVM.InstrOperand]
  -> [TM.Location]
  -> OpStructure
  -> Either String OpStructure
     -- ^ An error message or the generated 'OpStructure'.
addOperandConstraints ops all_locs os =
  foldM processOp os ops
  where processOp os' (LLVM.RegInstrOperand op_name reg_names) =
          do locs <- mapM getIDOfLocWithName reg_names
             n <- getValueNode os' op_name
             return os' { osValidLocations = osValidLocations os'
                                             ++ [(getNodeID n, locs)]
                        }
        processOp os' (LLVM.ImmInstrOperand op_name range) =
          do n <- getValueNode os' op_name
             let old_dt = getDataTypeOfValueNode n
                 -- It is assumed that the value node for an immediate is always
                 -- a temporary at this point
                 new_dt = D.IntConstType range (Just $ D.intTempNumBits old_dt)
                 new_g = updateDataTypeOfValueNode new_dt n (osGraph os')
             return os' { osGraph = new_g }
        processOp os' (LLVM.AbsAddrInstrOperand op_name range) =
          do n <- getValueOrBlockOrCallNode os' op_name
             addAddressConstraints os' n range
        processOp os' (LLVM.RelAddrInstrOperand op_name range) =
          do n <- getValueOrBlockOrCallNode os' op_name
             addAddressConstraints os' n range
        getValueNode os' origin =
          do let n = findValueNodesWithOrigin (osGraph os') origin
             if length n == 1
             then return $ head n
             else if length n > 0
                  then Left $ "addOperandConstraints: multiple value nodes "
                              ++ "with origin '" ++ origin ++ "'"
                  else Left $ "addOperandConstraints: no value node with "
                              ++ "origin '" ++ origin ++ "'"
        getValueOrBlockOrCallNode os' str =
          do let value_n = findValueNodesWithOrigin (osGraph os') str
                 block_n = findBlockNodesWithName (osGraph os')
                           $ toBlockName str
             let call_n  = findCallNodesWithName (osGraph os')
                                                 (toFunctionName str)
                 all_n = value_n ++ block_n ++ call_n
             if length all_n == 1
             then return $ head all_n
             else if length all_n == 0
                  then Left $ "addOperandConstraints: no value, block, or "
                              ++ "call node with origin or name '" ++ str ++ "'"
                  else Left $ "addOperandConstraints: multiple value, block, "
                              ++ "or call nodes with origin or name '"
                              ++ str ++ "'"
        getIDOfLocWithName name =
          do let loc = filter (\l -> TM.locName l == TM.toLocationName name)
                              all_locs
             if length loc == 1
             then return $ TM.locID $ head loc
             else if length loc > 0
                  then Left $ "addOperandConstraints: multiple locations with "
                              ++ "name '" ++ name ++ "'"
                  else Left $ "addOperandConstraints: no location with name '"
                              ++ name ++ "'"
        addAddressConstraints os' n range
          | isValueNode n =
              -- It is assumed that the value node for an immediate is always a
              -- temporary at this point
              let old_dt = getDataTypeOfValueNode n
                  new_dt = D.IntConstType range (Just $ D.intTempNumBits old_dt)
                  new_g = updateDataTypeOfValueNode new_dt n (osGraph os')
              in return os' { osGraph = new_g }
          | isBlockNode n =
              -- TODO: implement
              return os'
          | isCallNode n = return os' -- Do nothing
          | otherwise =
              Left $ "addOperandConstraints: unexpected node type: " ++ show n

mkOpStructure
  :: LLVM.InstrSemantics
  -> Either String OpStructure
     -- ^ An error message or the generated 'OpStructure'.
mkOpStructure (LLVM.InstrSemantics (Right m)) =
  let m_defs = LLVM.moduleDefinitions m
      getFunction d =
        case d of (LLVM.GlobalDefinition f@(LLVM.Function {})) -> Just f
                  _ -> Nothing
      isSemanticsFunction f =
        case (LLVM.name f) of (LLVM.Name name) -> name == "semantics"
                              _ -> False
      fs = mapMaybe getFunction m_defs
      sem_f = filter isSemanticsFunction fs
  in if length sem_f == 1
     then mkPatternOS $ head sem_f
     else if length sem_f == 0
          then error "mkOpStructure: no semantics function found"
          else error "mkOpStructure: multiple semantics function found"
mkOpStructure (LLVM.InstrSemantics (Left _)) =
  error "mkOpStructure: instruction semantics has not been parsed"

mkEmitString
  :: LLVM.Instruction
  -> OpStructure
  -> String
  -> Either String TM.EmitStringTemplate
     -- ^ An error message or the generated 'TM.EmitStringTemplate'.
mkEmitString i os str =
  do let ls = splitOn "\n" str
         ls_parts = map (splitStartingOn "% ,()[]") ls
     t_parts <- mapM (mapM mkES) ls_parts
     let merged_t_parts = filter (\l -> l /= [])
                          $ map mergeVerbatims t_parts
     return $ TM.EmitStringTemplate merged_t_parts
  where
  mkES s =
    if head s == '%'
    then if not (isNumeric (tail s))
         then let g = osGraph os
                  value_n = findValueNodesWithOrigin g s
                  block_n = findBlockNodesWithName g $ toBlockName s
                  call_n = findCallNodesWithName g $ toFunctionName s
                  all_n = value_n ++ block_n ++ call_n
              in if length all_n == 1
                 then mkESFromNode (head all_n) s
                 else Left $ "mkEmitString: no value, block, or call node "
                             ++ "with name '" ++ s ++ "'"
         else let int = read $ tail s
              in return $ TM.ESLocalTemporary int
    else return $ TM.ESVerbatim s
  mkESFromNode n s
    | isValueNode n =
        let op = getInstrOperand i s
        in if isJust op
           then case (fromJust op)
                of (LLVM.RegInstrOperand {}) ->
                     return $ TM.ESLocationOfValueNode $ getNodeID n
                   (LLVM.ImmInstrOperand {}) ->
                     return $ TM.ESIntConstOfValueNode $ getNodeID n
                   _ -> Left $ "mkEmitString: unknown instruction operand "
                               ++ "type: " ++ show op
           else Left $ "mkEmitString: no instruction operand with name '"
                       ++ s ++ "'"
    | isBlockNode n =
        let op = getInstrOperand i s
        in if isJust op
           then case (fromJust op)
                of (LLVM.AbsAddrInstrOperand {}) ->
                     return $ TM.ESNameOfBlockNode $ getNodeID n
                   (LLVM.RelAddrInstrOperand {}) ->
                     return $ TM.ESNameOfBlockNode $ getNodeID n
                   _ -> Left $ "mkEmitString: unknown instruction operand "
                               ++ "type: " ++ show op
           else Left $ "mkEmitString: no instruction operand with name '"
                       ++ s ++ "'"
    | isCallNode n = return $ TM.ESFuncOfCallNode $ getNodeID n
    | otherwise = Left $ "mkEmitString: unexpected node type: " ++ show n
  mergeVerbatims [] = []
  mergeVerbatims [s] = [s]
  mergeVerbatims (TM.ESVerbatim s1:TM.ESVerbatim s2:ss) =
    mergeVerbatims (TM.ESVerbatim (s1 ++ s2):ss)
  mergeVerbatims (s:ss) = (s:mergeVerbatims ss)

mkInstrProps :: LLVM.Instruction -> TM.InstrProperties
mkInstrProps i=
  TM.InstrProperties { TM.instrCodeSize = LLVM.instrSize i
                     , TM.instrLatency = LLVM.instrLatency i
                     , TM.instrIsInactive = False
                     }

-- | Gets the operand with a given name of a given instruction. If no such
-- operand is found, 'Nothing' is returned.
getInstrOperand :: LLVM.Instruction -> String -> Maybe LLVM.InstrOperand
getInstrOperand i name =
  let op = filter (\o -> LLVM.opName o == name)
           $ LLVM.instrOperands
           $ head -- Which pattern we take does not matter in this context
           $ LLVM.instrPatterns i
  in if length op > 0
     then Just $ head op
     else Nothing
