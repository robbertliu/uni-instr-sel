--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstrSel.OpStructures.LLVM.OSMaker
-- Copyright   : (c) Gabriel Hjort Blindell 2013-2015
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Builds an 'OpStructure' from a given LLVM function.
--
--------------------------------------------------------------------------------

module Language.InstrSel.OpStructures.LLVM.OSMaker
  ( mkFromFunction
  , toSymbolString
  )
where

import qualified Language.InstrSel.DataTypes as D
import qualified Language.InstrSel.Graphs as G
import qualified Language.InstrSel.OpStructures as OS
import qualified Language.InstrSel.OpTypes as Op
import qualified Language.InstrSel.Functions as F
import Language.InstrSel.Utils
  ( rangeFromSingleton
  , toNatural
  )

import qualified LLVM.General.AST as LLVM
import qualified LLVM.General.AST.Constant as LLVMC
import qualified LLVM.General.AST.FloatingPointPredicate as LLVMF
import qualified LLVM.General.AST.Global as LLVMG
import qualified LLVM.General.AST.IntegerPredicate as LLVMI

import Data.Maybe



--------------
-- Data types
--------------

-- | Represents a mapping from a symbol to a value node currently in the graph.
type SymToValueNodeMapping = (Symbol, G.Node)

-- | Represents a data flow that goes from a block node, identified by the given
-- ID, to an datum node. This is needed to draw the missing flow edges after
-- both the data-flow graph and the control-flow graph have been built.
type BlockToDatumDataFlow = (F.BlockName, G.Node)

-- | Represents a definition that goes from a block node, identified by the
-- given ID, an datum node. This is needed to draw the missing definition edges
-- after both the data-flow graph and the control-flow graph have been
-- built. Since the in-edge number of an data-flow edge must match that of the
-- corresponding definition edge, the in-edge number of the data-flow edge is
-- also included in the tuple.
type BlockToDatumDef = (F.BlockName, G.Node, G.EdgeNr)

-- | Represents a definition that goes from an datum node to a block node,
-- identified by the given ID. This is needed to draw the missing definition
-- edges after both the data-flow graph and the control-flow graph have been
-- built. Since the out-edge number of an data-flow edge must match that of the
-- corresponding definition edge, the out-edge number of the data-flow edge is
-- also included in the tuple.
type DatumToBlockDef = (G.Node, F.BlockName, G.EdgeNr)

-- | Represents the intermediate build data.
data BuildState
  = BuildState
      { opStruct :: OS.OpStructure
        -- ^ The current operation structure.
      , lastTouchedNode :: Maybe G.Node
        -- ^ The last node (if any) that was touched. This is used to
        -- simplifying edge insertion.
      , entryBlock :: Maybe F.BlockName
        -- ^ The block of the function entry point. A 'Nothing' value means that
        -- this value has not yet been assigned.
      , currentBlock :: Maybe F.BlockName
        -- ^ The block of the basic block currently being processed. A 'Nothing'
        -- value means that no basic block has yet been processed.
      , symMaps :: [SymToValueNodeMapping]
        -- ^ List of symbol-to-node mappings. If there are more than one mapping
        -- using the same symbol, then the last one occuring in the list should
        -- be picked.
      , blockToDatumDataFlows :: [BlockToDatumDataFlow]
        -- ^ List of block-to-datum flow dependencies that are yet to be
        -- converted into edges.
      , blockToDatumDefs :: [BlockToDatumDef]
        -- ^ List of block-to-datum definitions that are yet to be converted
        -- into edges.
      , datumToBlockDefs :: [DatumToBlockDef]
        -- ^ List of datum-to-block definitions that are yet to be converted
        -- into edges.
      , funcInputValues :: [G.Node]
        -- ^ The value nodes representing the function input arguments.
      }
  deriving (Show)

-- | Retains various symbol names.
data Symbol
  = LocalStringSymbol String
  | GlobalStringSymbol String
  | TemporarySymbol Integer
  deriving (Eq)

instance Show Symbol where
  show (LocalStringSymbol str) = "%" ++ str
  show (GlobalStringSymbol str) = "@" ++ str
  show (TemporarySymbol int) = "t" ++ show int

-- | Retains various constant values.
data Constant
  = IntConstant
      { intBitWidth :: Integer
        -- ^ Number of bits that represents the integer value.
      , signedIntValue :: Integer
        -- ^ The integer value. Note that this value is the signed-interpreted
        -- value of the value provided in the LLVM AST (see
        -- 'LLVMC.signedIntegerValue').
      }

  | FloatConstant { floatValue :: Float }
  | GlobalReferenceConstant { globalRefType :: D.DataType
                            , globalRefName :: Symbol
                            }
  deriving (Eq)

instance Show Constant where
  show IntConstant { signedIntValue = v } = show v
  show FloatConstant { floatValue = v } = show v
  show GlobalReferenceConstant { globalRefName = s } = show s


----------------
-- Type classes
----------------

-- | Class for converting an LLVM symbol datum into a 'Symbol'.
class SymbolFormable a where
  toSymbol :: a -> Symbol

instance SymbolFormable LLVM.Name where
  toSymbol (LLVM.Name str) = LocalStringSymbol str
  toSymbol (LLVM.UnName int) = TemporarySymbol $ toInteger int

-- | Class for converting an LLVM constant datum into a 'Constant'.
class ConstantFormable a where
  toConstant :: a -> Constant

instance ConstantFormable LLVMC.Constant where
  toConstant i@(LLVMC.Int b _) =
    IntConstant { intBitWidth = fromIntegral b
                , signedIntValue = LLVMC.signedIntegerValue i
                }
  toConstant (LLVMC.GlobalReference t n) =
    GlobalReferenceConstant { globalRefType = toDataType t
                            , globalRefName = toSymbol n
                            }
  toConstant l = error $ "'toConstant' not implemented for " ++ show l

-- | Class for converting an LLVM datum into a 'DataType'.
class DataTypeFormable a where
  toDataType :: a -> D.DataType

instance DataTypeFormable Constant where
  toDataType IntConstant { intBitWidth = w, signedIntValue = v } =
    D.IntConstType { D.intConstValue = rangeFromSingleton v
                   , D.intConstNumBits = Just $ toNatural w
                   }
  toDataType GlobalReferenceConstant {} =
    -- TODO: fix so that the correct data type is applied
    D.AnyType
  toDataType c = error $ "'toDataType' not implemented for " ++ show c

instance DataTypeFormable LLVM.Type where
  toDataType (LLVM.IntegerType bits) =
    D.IntTempType { D.intTempNumBits = toNatural bits }
  toDataType (LLVM.PointerType _ _) =
    -- TODO: fix so that the correct data type is applied
    D.AnyType
  toDataType t = error $ "'toDataType' not implemented for " ++ show t

instance DataTypeFormable LLVM.Operand where
  toDataType (LLVM.LocalReference t _) = toDataType t
  toDataType (LLVM.ConstantOperand c) = toDataType (toConstant c)
  toDataType o = error $ "'toDataType' not implemented for " ++ show o

-- | Class for building the data-flow graph.
class DfgBuildable a where
  -- | Builds the corresponding data-flow graph from a given LLVM element.
  buildDfg
    :: BuildState
      -- ^ The current build state.
    -> a
       -- ^ The LLVM element to process.
    -> BuildState
       -- ^ The new build state.

-- | Class for building the control-flow graph.
class CfgBuildable a where
  -- | Builds the corresponding control-flow graph from a given LLVM element.
  -- It is assumed that all data referred to in the resulting CFG are already
  -- available in the current build state.
  buildCfg
    :: BuildState
      -- ^ The current build state.
    -> a
       -- ^ The LLVM element to process.
    -> BuildState
       -- ^ The new build state.



-------------
-- Functions
-------------

-- | Converts a 'SymbolFormable' entity into a string. This is typically used
-- when referring to nodes whose name or origin is based on an LLVM entity (such
-- as a temporary or a variable).
toSymbolString :: (SymbolFormable s) => s -> String
toSymbolString = show . toSymbol

-- | Builds an 'OpStructure' from a global LLVM function. If the definition is
-- not a 'Function', an error is produced.
mkFromFunction :: LLVM.Global -> OS.OpStructure
mkFromFunction f@(LLVM.Function {}) =
  let st0 = mkInitBuildState
      st1 = buildDfg st0 f
      st2 = buildCfg st1 f
      st3 = updateOSEntryBlockNode
              st2
              (fromJust $ findBlockNodeWithID st2 (fromJust $ entryBlock st2))
      st4 = addMissingBlockToDatumDataFlowEdges st3
      st5 = addMissingBlockToDatumDefEdges st4
      st6 = addMissingDatumToBlockDefEdges st5
  in opStruct st6
mkFromFunction _ = error "mkOpStructureFromGlobal: not a Function"

-- | Creates an initial state.
mkInitBuildState :: BuildState
mkInitBuildState =
  BuildState { opStruct = OS.mkEmpty
             , lastTouchedNode = Nothing
             , entryBlock = Nothing
             , currentBlock = Nothing
             , symMaps = []
             , blockToDatumDataFlows = []
             , blockToDatumDefs = []
             , datumToBlockDefs = []
             , funcInputValues = []
             }

-- | Converts an argument into a temporary-oriented data type.
toTempDataType :: (DataTypeFormable t) => t -> D.DataType
toTempDataType a =
  conv $ toDataType a
  where conv d@(D.IntTempType {}) = d
        conv (D.IntConstType { D.intConstNumBits = b }) =
          if isJust b
          then D.IntTempType { D.intTempNumBits = fromJust b }
          else error $ "toTempDataType: IntConstType has 'intTempNumBits' "
                       ++ "set to 'Nothing'"
        conv d = error $ "toTempDataType: unexpected data type " ++ show d

-- | Gets the OS graph contained by the operation structure in a given state.
getOSGraph :: BuildState -> G.Graph
getOSGraph = OS.osGraph . opStruct

-- | Updates the OS graph contained by the operation structure in a given state.
updateOSGraph :: BuildState -> G.Graph -> BuildState
updateOSGraph st g =
  let os = opStruct st
  in st { opStruct = os { OS.osGraph = g } }

-- | Updates the OS entry block node contained by the operation structure in a
-- given state.
updateOSEntryBlockNode :: BuildState -> G.Node -> BuildState
updateOSEntryBlockNode st n =
  let os = opStruct st
  in st { opStruct = os { OS.osEntryBlockNode = Just (G.getNodeID n) } }

-- | Updates the last touched node information.
touchNode :: BuildState -> G.Node -> BuildState
touchNode st n = st { lastTouchedNode = Just n }

-- | Adds a new node into a given state.
addNewNode :: BuildState -> G.NodeType -> BuildState
addNewNode st0 nt =
  let (new_g, new_n) = G.addNewNode nt (getOSGraph st0)
      st1 = updateOSGraph st0 new_g
      st2 = touchNode st1 new_n
  in st2

mkVarNameForConst :: Constant -> String
mkVarNameForConst c = "%const." ++ (show c)

-- | Adds a new value node representing a particular constant to a given state.
addNewValueNodeWithConstant :: BuildState -> Constant -> BuildState
addNewValueNodeWithConstant st0 c =
  -- TODO: fix so that each constant gets a unique variable name
  let st1 = addNewNode st0 ( G.ValueNode (toDataType c)
                                         (Just $ mkVarNameForConst c)
                           )
      new_n = fromJust $ lastTouchedNode st1
      st2 = addBlockToDatumDataFlow st1 (fromJust $ entryBlock st1, new_n)
  in st2

-- | Adds a new edge into a given state.
addNewEdge
  :: BuildState
     -- ^ The current state.
  -> G.EdgeType
  -> G.Node
     -- ^ The source node.
  -> G.Node
     -- ^ The destination node.
  -> BuildState
     -- ^ The new state.
addNewEdge st et src dst =
  let (new_g, _) = G.addNewEdge et (src, dst) (getOSGraph st)
  in updateOSGraph st new_g

-- | Adds many new edges of the same type into a given state.
addNewEdgesManySources
  :: BuildState
     -- ^ The current state.
  -> G.EdgeType
  -> [G.Node]
     -- ^ The source nodes.
  -> G.Node
     -- ^ The destination node.
  -> BuildState
     -- ^ The new state.
addNewEdgesManySources st et srcs dst =
  let es = zip srcs (repeat dst)
      f g e = fst $ G.addNewEdge et e g
  in updateOSGraph st $ foldl f (getOSGraph st) es

-- | Adds many new edges of the same type into a given state.
addNewEdgesManyDests
  :: BuildState
     -- ^ The current state.
  -> G.EdgeType
  -> G.Node
     -- ^ The source node.
  -> [G.Node]
     -- ^ The destination nodes.
  -> BuildState
     -- ^ The new state.
addNewEdgesManyDests st et src dsts =
  let es = zip (repeat src) dsts
      f g e = fst $ G.addNewEdge et e g
  in updateOSGraph st $ foldl f (getOSGraph st) es

-- | Adds a new symbol-to-node mapping to a given state.
addSymMap :: BuildState -> SymToValueNodeMapping -> BuildState
addSymMap st sm = st { symMaps = sm:(symMaps st) }

-- | Adds block-to-datum flow to a given state.
addBlockToDatumDataFlow :: BuildState -> BlockToDatumDataFlow -> BuildState
addBlockToDatumDataFlow st flow =
  st { blockToDatumDataFlows = flow:(blockToDatumDataFlows st) }

-- | Adds block-to-datum definition to a given state.
addBlockToDatumDef :: BuildState -> BlockToDatumDef -> BuildState
addBlockToDatumDef st def =
  st { blockToDatumDefs = def:(blockToDatumDefs st) }

-- | Adds datum-to-block definition to a given state.
addDatumToBlockDef :: BuildState -> DatumToBlockDef -> BuildState
addDatumToBlockDef st def =
  st { datumToBlockDefs = def:(datumToBlockDefs st) }

-- | Adds a value node representing a function argument to a given state.
addFuncInputValue :: BuildState -> G.Node -> BuildState
addFuncInputValue st n =
  st { funcInputValues = n:(funcInputValues st) }

-- | Finds the node ID (if any) of the value node to which a symbol is mapped.
findValueNodeWithSym :: BuildState -> Symbol -> Maybe G.Node
findValueNodeWithSym st sym = lookup sym (symMaps st)

-- | Gets the block node with a particular name in the graph of the given state.
-- If no such node exists, 'Nothing' is returned.
findBlockNodeWithID :: BuildState -> F.BlockName -> Maybe G.Node
findBlockNodeWithID st l =
  let block_nodes = filter G.isBlockNode $ G.getAllNodes $ getOSGraph st
      nodes_w_matching_blocks =
        filter (\n -> (G.nameOfBlock $ G.getNodeType n) == l) block_nodes
  in if length nodes_w_matching_blocks > 0
     then Just (head nodes_w_matching_blocks)
     else Nothing

-- | Checks that a value node with a particular symbol exists in the graph of
-- the given state. If it does then the last touched node is updated
-- accordingly, otherwise a new value node with the symbol is added. A
-- corresponding mapping is also added.
ensureValueNodeWithSymExists
  :: BuildState
  -> Symbol
  -> D.DataType
     -- ^ Data type to use upon creation if such a value node does not exist.
  -> BuildState
ensureValueNodeWithSymExists st0 sym dt =
  let n = findValueNodeWithSym st0 sym
  in if isJust n
     then touchNode st0 (fromJust n)
     else let st1 = addNewNode st0 (G.ValueNode dt (Just $ show sym))
              new_n = fromJust $ lastTouchedNode st1
              st2 = addSymMap st1 (sym, new_n)
          in st2

-- | Checks that a block node with a particular name exists in the graph of the
-- given state. If it does then the last touched node is updated accordingly,
-- otherwise then a new block node is added.
ensureBlockNodeExists :: BuildState -> F.BlockName -> BuildState
ensureBlockNodeExists st l =
  let block_node = findBlockNodeWithID st l
  in if isJust block_node
     then touchNode st (fromJust block_node)
     else addNewNode st (G.BlockNode l)

-- | Inserts a new computation node representing the operation along with edges
-- to that computation node from the given operands (which will also be
-- processed). Lastly, a new value node representing the result will be added
-- along with an edge to that value node from the computation node.
buildDfgFromCompOp
  :: (DfgBuildable o)
  => BuildState
  -> D.DataType
     -- ^ The data type of the result.
  -> Op.CompOp
     -- ^ The computational operation.
  -> [o]
     -- ^ The operands.
  -> BuildState
buildDfgFromCompOp st0 dt op operands =
  let sts = scanl buildDfg st0 operands
      operand_ns = map (fromJust . lastTouchedNode) (tail sts)
      st1 = last sts
      st2 = addNewNode st1 (G.ComputationNode op)
      op_node = fromJust $ lastTouchedNode st2
      st3 = addNewEdgesManySources st2 G.DataFlowEdge operand_ns op_node
      st4 = addNewNode st3 (G.ValueNode dt Nothing)
      d_node = fromJust $ lastTouchedNode st4
      st5 = addNewEdge st4 G.DataFlowEdge op_node d_node
  in st5

-- | Inserts a new node representing a control operation, and adds edges to that
-- node from the current block node and operands (which will also be processed).
buildCfgFromControlOp
  :: (CfgBuildable o)
  => BuildState
  -> Op.ControlOp
     -- ^ The control operation.
  -> [o]
     -- ^ The operands.
  -> BuildState
buildCfgFromControlOp st0 op operands =
  let sts = scanl buildCfg st0 operands
      operand_ns = map (fromJust . lastTouchedNode) (tail sts)
      st1 = last sts
      st2 = addNewNode st1 (G.ControlNode op)
      op_node = fromJust $ lastTouchedNode st2
      st3 = addNewEdge st2
                       G.ControlFlowEdge
                       ( fromJust $
                           findBlockNodeWithID st2
                                               (fromJust $ currentBlock st2)
                       )
              op_node
      st4 = addNewEdgesManySources st3 G.DataFlowEdge operand_ns op_node
  in st4

-- | Converts an LLVM integer comparison op into an equivalent op of our own
-- data type.
fromLlvmIPred :: LLVMI.IntegerPredicate -> Op.CompOp
fromLlvmIPred LLVMI.EQ  = Op.CompArithOp $  Op.IntOp Op.Eq
fromLlvmIPred LLVMI.NE  = Op.CompArithOp $  Op.IntOp Op.NEq
fromLlvmIPred LLVMI.UGT = Op.CompArithOp $ Op.UIntOp Op.GT
fromLlvmIPred LLVMI.ULT = Op.CompArithOp $ Op.UIntOp Op.LT
fromLlvmIPred LLVMI.UGE = Op.CompArithOp $ Op.UIntOp Op.GE
fromLlvmIPred LLVMI.ULE = Op.CompArithOp $ Op.UIntOp Op.LE
fromLlvmIPred LLVMI.SGT = Op.CompArithOp $ Op.SIntOp Op.GT
fromLlvmIPred LLVMI.SLT = Op.CompArithOp $ Op.SIntOp Op.LT
fromLlvmIPred LLVMI.SGE = Op.CompArithOp $ Op.SIntOp Op.GE
fromLlvmIPred LLVMI.SLE = Op.CompArithOp $ Op.SIntOp Op.LE

-- | Converts an LLVM floating point comparison op into an equivalent op of our
-- own data type.
fromLlvmFPred :: LLVMF.FloatingPointPredicate -> Op.CompOp
fromLlvmFPred LLVMF.OEQ = Op.CompArithOp $ Op.OFloatOp Op.Eq
fromLlvmFPred LLVMF.ONE = Op.CompArithOp $ Op.OFloatOp Op.NEq
fromLlvmFPred LLVMF.OGT = Op.CompArithOp $ Op.OFloatOp Op.GT
fromLlvmFPred LLVMF.OGE = Op.CompArithOp $ Op.OFloatOp Op.GE
fromLlvmFPred LLVMF.OLT = Op.CompArithOp $ Op.OFloatOp Op.LT
fromLlvmFPred LLVMF.OLE = Op.CompArithOp $ Op.OFloatOp Op.LE
fromLlvmFPred LLVMF.ORD = Op.CompArithOp $  Op.FloatOp Op.Ordered
fromLlvmFPred LLVMF.UNO = Op.CompArithOp $  Op.FloatOp Op.Unordered
fromLlvmFPred LLVMF.UEQ = Op.CompArithOp $ Op.UFloatOp Op.Eq
fromLlvmFPred LLVMF.UGT = Op.CompArithOp $ Op.UFloatOp Op.GT
fromLlvmFPred LLVMF.UGE = Op.CompArithOp $ Op.UFloatOp Op.GE
fromLlvmFPred LLVMF.ULT = Op.CompArithOp $ Op.UFloatOp Op.LT
fromLlvmFPred LLVMF.ULE = Op.CompArithOp $ Op.UFloatOp Op.LE
fromLlvmFPred LLVMF.UNE = Op.CompArithOp $ Op.UFloatOp Op.NEq
fromLlvmFPred op = error $ "'fromLlvmFPred' not implemented for " ++ show op

-- | Adds the missing data or state flow edges from block nodes to data or state
-- nodes, as described in the given build state.
addMissingBlockToDatumDataFlowEdges :: BuildState -> BuildState
addMissingBlockToDatumDataFlowEdges st =
  let g0 = getOSGraph st
      deps = map ( \(l, n) ->
                   if G.isValueNode n
                   then (l, n, G.DataFlowEdge)
                   else if G.isStateNode n
                        then (l, n, G.StateFlowEdge)
                        else error ( "addMissingBlockToDatumDataFlowEdges: "
                                     ++ "This should never happen"
                                   )
                 )
                 (blockToDatumDataFlows st)
      g1 =
        foldr ( \(l, n, et) g ->
                let pair = (fromJust $ findBlockNodeWithID st l, n)
                in fst $ G.addNewEdge et pair g
              )
              g0
              deps
  in updateOSGraph st g1

-- | Adds the missing block-to-datum definition edges, as described in the
-- given build state.
addMissingBlockToDatumDefEdges :: BuildState -> BuildState
addMissingBlockToDatumDefEdges st =
  let g0 = getOSGraph st
      defs = blockToDatumDefs st
      g1 = foldr ( \(block_id, dn, nr) g ->
                   let ln = fromJust $ findBlockNodeWithID st block_id
                       (g', new_e) = G.addNewDefEdge (ln, dn) g
                       new_el = (G.getEdgeLabel new_e) { G.inEdgeNr = nr }
                       g'' = G.updateEdgeLabel new_el new_e g'
                   in g''
                 )
                 g0
                 defs
  in updateOSGraph st g1

-- | Adds the missing datum-to-block definition edges, as described in the
-- given build state.
addMissingDatumToBlockDefEdges :: BuildState -> BuildState
addMissingDatumToBlockDefEdges st =
  let g0 = getOSGraph st
      defs = datumToBlockDefs st
      g1 = foldr ( \(dn, block_id, nr) g ->
                   let ln = fromJust $ findBlockNodeWithID st block_id
                       (g', new_e) = G.addNewDefEdge (dn, ln) g
                       new_el = (G.getEdgeLabel new_e) { G.outEdgeNr = nr }
                       g'' = G.updateEdgeLabel new_el new_e g'
                   in g''
                 )
                 g0
                 defs
  in updateOSGraph st g1

-- | Gets the LLVM instruction from a named expression.
fromNamed :: LLVM.Named i -> i
fromNamed (_ LLVM.:= i) = i
fromNamed (LLVM.Do i) = i



---------------------------------------------
-- DfgBuildable-related type class instances
---------------------------------------------

instance (DfgBuildable a) => DfgBuildable [a] where
  buildDfg = foldl buildDfg

instance (DfgBuildable n) => DfgBuildable (LLVM.Named n) where
  buildDfg st0 (name LLVM.:= expr) =
    let st1 = buildDfg st0 expr
        sym = toSymbol name
        res_n = fromJust $ lastTouchedNode st1
        res_dt = G.getDataTypeOfValueNode res_n
        st2 = ensureValueNodeWithSymExists st1 sym res_dt
        sym_n = fromJust $ lastTouchedNode st2
        st3 = updateOSGraph st2 (G.mergeNodes sym_n res_n (getOSGraph st2))
        replaceNodeInLEDef old_n new_n (l, n, nr) =
          if old_n == n then (l, new_n, nr) else (l, n, nr)
        st4 = st3 { blockToDatumDefs =
                       map (replaceNodeInLEDef res_n sym_n)
                           (blockToDatumDefs st3)
                  }
        replaceNodeInELDef old_n new_n (n, l, nr) =
          if old_n == n then (new_n, l, nr) else (n, l, nr)
        st5 = st4 { datumToBlockDefs =
                       map (replaceNodeInELDef res_n sym_n)
                           (datumToBlockDefs st4)
                  }
    in st5
  buildDfg st (LLVM.Do expr) = buildDfg st expr

instance DfgBuildable LLVM.Global where
  buildDfg st0 f@(LLVM.Function {}) =
    let (params, _) = LLVMG.parameters f
        st1 = buildDfg st0 params
        st2 = buildDfg st1 $ LLVMG.basicBlocks f
    in st2
  buildDfg _ l = error $ "'buildDfg' not implemented for " ++ show l

instance DfgBuildable LLVM.BasicBlock where
  buildDfg st0 (LLVM.BasicBlock (LLVM.Name str) insts _) =
    let block_name = F.BlockName str
        st1 = if isNothing $ entryBlock st0
              then foldl (\st n -> addBlockToDatumDataFlow st (block_name, n))
                         (st0 { entryBlock = Just block_name })
                         (funcInputValues st0)
              else st0
        st2 = st1 { currentBlock = Just block_name }
        st3 = foldl buildDfg st2 insts
    in st3
  buildDfg _ (LLVM.BasicBlock (LLVM.UnName _) _ _) =
    error $ "'buildDfg' does not support unnamed basic blocks"

instance DfgBuildable LLVM.Instruction where
  buildDfg st (LLVM.Add  nsw nuw op1 op2 _) =
    -- TODO: make use of nsw and nuw?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.Add)
                       [op1, op2]
  buildDfg st (LLVM.FAdd _ op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.FloatOp Op.Add)
                       [op1, op2]
  buildDfg st (LLVM.Sub  nsw nuw op1 op2 _) =
    -- TODO: make use of nsw and nuw?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.Sub)
                       [op1, op2]
  buildDfg st (LLVM.FSub _ op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.FloatOp Op.Sub)
                       [op1, op2]
  buildDfg st (LLVM.Mul nsw nuw op1 op2 _) =
    -- TODO: make use of nsw and nuw?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.Mul)
                       [op1, op2]
  buildDfg st (LLVM.FMul _ op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.FloatOp Op.Mul)
                       [op1, op2]
  buildDfg st (LLVM.UDiv exact op1 op2 _) =
    -- TODO: make use of exact?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.UIntOp Op.Div)
                       [op1, op2]
  buildDfg st (LLVM.SDiv exact op1 op2 _) =
    -- TODO: make use of exact?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.SIntOp Op.Div)
                       [op1, op2]
  buildDfg st (LLVM.FDiv _ op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.FloatOp Op.Div)
                       [op1, op2]
  buildDfg st (LLVM.URem op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.UIntOp Op.Rem)
                       [op1, op2]
  buildDfg st (LLVM.SRem op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.SIntOp Op.Rem)
                       [op1, op2]
  buildDfg st (LLVM.FRem _ op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.FloatOp Op.Rem)
                       [op1, op2]
  buildDfg st (LLVM.Shl nsw nuw op1 op2 _) =
    -- TODO: make use of nsw and nuw?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.Shl)
                       [op1, op2]
  buildDfg st (LLVM.LShr exact op1 op2 _) =
    -- TODO: make use of exact?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.LShr)
                       [op1, op2]
  buildDfg st (LLVM.AShr exact op1 op2 _) =
    -- TODO: make use of exact?
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.AShr)
                       [op1, op2]
  buildDfg st (LLVM.And op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.And)
                       [op1, op2]
  buildDfg st (LLVM.Or op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.Or)
                       [op1, op2]
  buildDfg st (LLVM.Xor op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (Op.CompArithOp $ Op.IntOp Op.XOr)
                       [op1, op2]
  buildDfg st (LLVM.ICmp p op1 op2 _) =
    -- TODO: add support for vectorized icmp
    buildDfgFromCompOp st
                       (D.IntTempType { D.intTempNumBits = 1 })
                       (fromLlvmIPred p)
                       [op1, op2]
  buildDfg st (LLVM.FCmp p op1 op2 _) =
    buildDfgFromCompOp st
                       (toTempDataType op1)
                       (fromLlvmFPred p)
                       [op1, op2]
  buildDfg st (LLVM.Trunc op1 t1 _) =
    buildDfgFromCompOp st
                       (toDataType t1)
                       (Op.CompTypeConvOp Op.Trunc)
                       [op1]
  buildDfg st (LLVM.ZExt op1 t1 _) =
    buildDfgFromCompOp st
                       (toDataType t1)
                       (Op.CompTypeConvOp Op.ZExt)
                       [op1]
  buildDfg st (LLVM.SExt op1 t1 _) =
    buildDfgFromCompOp st
                       (toDataType t1)
                       (Op.CompTypeConvOp Op.SExt)
                       [op1]
  -- TODO: replace the 'addDatumToBlockDef' with proper dependencies from/to
  -- state nodes.
  buildDfg st0 (LLVM.Load _ op1 _ _ _) =
    let st1 = buildDfgFromCompOp st0
                        (toDataType op1)
                        (Op.CompMemoryOp Op.Load)
                        [op1]
        n   = fromJust $ lastTouchedNode st1
        bb  = fromJust $ currentBlock st1
        st2 = addDatumToBlockDef st1 (n, bb, 0)
    in st2
  -- TODO: replace the 'addDatumToBlockDef' with proper dependencies from/to
  -- state nodes.
  buildDfg st0 (LLVM.Store _ op1 op2 _ _ _) =
    let st1 = buildDfgFromCompOp st0
                        D.AnyType -- This doesn't matter since the result node
                                  -- will be removed directly afterwards
                        (Op.CompMemoryOp Op.Store)
                        [op1, op2] -- TODO: check the order that it's correct
        -- TODO: remove the node below
        n   = fromJust $ lastTouchedNode st1
    in st1
  buildDfg st0 (LLVM.Phi t phi_operands _) =
    let (operands, blocks) = unzip phi_operands
        block_names = map (\(LLVM.Name str) -> F.BlockName str) blocks
        operand_node_sts = scanl buildDfg st0 operands
        operand_ns = map (fromJust . lastTouchedNode) (tail operand_node_sts)
        st1 = last operand_node_sts
        st2 = addNewNode st1 G.PhiNode
        phi_node = fromJust $ lastTouchedNode st2
        st3 = addNewEdgesManySources st2 G.DataFlowEdge operand_ns phi_node
        st4 = foldl ( \st (n, block_id) ->
                      let g = getOSGraph st
                          dfe = head
                                $ filter G.isDataFlowEdge
                                $ G.getEdges g n phi_node
                      in addDatumToBlockDef st
                                             (n, block_id, G.getOutEdgeNr dfe)
                    )
                    st3
                    (zip operand_ns block_names)
        st5 = addNewNode st4 (G.ValueNode (toDataType t) Nothing)
        d_node = fromJust $ lastTouchedNode st5
        st6 = addNewEdge st5 G.DataFlowEdge phi_node d_node
        st7 = addBlockToDatumDef st6 (fromJust $ currentBlock st6, d_node, 0)
              -- Since we've just created the value node and only added a
              -- single data-flow edge to it, we are guaranteed that the in-edge
              -- number of that data-flow edge is 0.
    in st7
  buildDfg _ l = error $ "'buildDfg' not implemented for " ++ show l

instance DfgBuildable LLVM.Operand where
  buildDfg st (LLVM.LocalReference t name) =
    ensureValueNodeWithSymExists st (toSymbol name) (toDataType t)
  buildDfg st (LLVM.ConstantOperand c) =
    addNewValueNodeWithConstant st (toConstant c)
  buildDfg _ o = error $ "'buildDfg' not implemented for " ++ show o

instance DfgBuildable LLVM.Parameter where
  buildDfg st0 (LLVM.Parameter t name _) =
    let st1 = ensureValueNodeWithSymExists st0 (toSymbol name) (toDataType t)
        n = fromJust $ lastTouchedNode st1
        st2 = addFuncInputValue st1 n
    in st2



---------------------------------------------
-- CfgBuildable-related type class instances
---------------------------------------------

instance (CfgBuildable a) => CfgBuildable [a] where
  buildCfg = foldl buildCfg

instance CfgBuildable LLVM.BasicBlock where
  buildCfg st0 (LLVM.BasicBlock (LLVM.Name str) _ named_term_inst) =
    let block_name = F.BlockName str
        term_inst = fromNamed named_term_inst
        st1 = if isNothing $ entryBlock st0
              then st1 { entryBlock = Just block_name }
              else st0
        st2 = ensureBlockNodeExists st1 block_name
        st3 = st2 { currentBlock = Just block_name }
        st4 = buildCfg st3 term_inst
    in st4
  buildCfg _ (LLVM.BasicBlock (LLVM.UnName _) _ _) =
    error $ "'buildCfg' does not support unnamed basic blocks"

instance CfgBuildable LLVM.Global where
  buildCfg st f@(LLVM.Function {}) =
    buildCfg st $ LLVMG.basicBlocks f
  buildCfg _ l = error $ "'buildCfg' not implemented for " ++ show l

instance CfgBuildable LLVM.Terminator where
  buildCfg st (LLVM.Ret op _) =
    buildCfgFromControlOp st Op.Ret (maybeToList op)
  buildCfg st0 (LLVM.Br (LLVM.Name dst) _) =
    let st1 = buildCfgFromControlOp st0
                                    Op.Br
                                    ([] :: [LLVM.Operand])
                                    -- Signature needed to please GHC...
        br_node = fromJust $ lastTouchedNode st1
        st2 = ensureBlockNodeExists st1 (F.BlockName dst)
        dst_node = fromJust $ lastTouchedNode st2
        st3 = addNewEdge st2 G.ControlFlowEdge br_node dst_node
    in st3
  buildCfg st0 (LLVM.CondBr op (LLVM.Name t_dst) (LLVM.Name f_dst) _) =
    let st1 = buildCfgFromControlOp st0 Op.CondBr [op]
        br_node = fromJust $ lastTouchedNode st1
        st2 = ensureBlockNodeExists st1 (F.BlockName t_dst)
        t_dst_node = fromJust $ lastTouchedNode st2
        st3 = ensureBlockNodeExists st2 (F.BlockName f_dst)
        f_dst_node = fromJust $ lastTouchedNode st3
        st4 = addNewEdgesManyDests st3
                                   G.ControlFlowEdge
                                   br_node
                                   [t_dst_node, f_dst_node]
    in st4
  buildCfg _ l = error $ "'buildCfg' not implemented for " ++ show l

instance CfgBuildable LLVM.Operand where
  buildCfg st (LLVM.LocalReference t name) =
    ensureValueNodeWithSymExists st (toSymbol name) (toDataType t)
  buildCfg st (LLVM.ConstantOperand c) =
    addNewValueNodeWithConstant st (toConstant c)
  buildCfg _ o = error $ "'buildCfg' not implemented for " ++ show o