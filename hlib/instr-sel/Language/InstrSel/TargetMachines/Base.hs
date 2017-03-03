{-|
Copyright   :  Copyright (c) 2012-2017, Gabriel Hjort Blindell <ghb@kth.se>
License     :  BSD3 (see the LICENSE file)
Maintainer  :  ghb@kth.se
-}
{-
Main authors:
  Gabriel Hjort Blindell <ghb@kth.se>

-}

{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Language.InstrSel.TargetMachines.Base
  ( module Language.InstrSel.Graphs.IDs
  , module Language.InstrSel.TargetMachines.IDs
  , EmitStringTemplate (..)
  , EmitStringPart (..)
  , Instruction (..)
  , InstrPattern (..)
  , InstrProperties (..)
  , Location (..)
  , TargetMachine (..)
  , concatEmitStrings
  , getAllInstructions
  , getAllLocations
  , findInstruction
  , findInstrPattern
  , findLocation
  , isInstructionCopy
  , isInstructionInactive
  , isInstructionNull
  , isInstructionPhi
  , isInstructionSimd
  , replaceAllInstructions
  , replaceAllLocations
  , updateNodeInEmitStrTemplate
  )
where

import Language.InstrSel.Graphs.IDs
  ( NodeID )
import Language.InstrSel.Graphs
import Language.InstrSel.OpStructures
import Language.InstrSel.PrettyShow
import Language.InstrSel.TargetMachines.IDs
import Language.InstrSel.Utils
  ( Natural )

import qualified Data.Map as M

import Data.List
  ( intercalate )



--------------
-- Data types
--------------

-- | Represents the emit string template, which are used to produce the assembly
-- instructions during code emission. Each element in the outer list corresponds
-- to a single line of code.
data EmitStringTemplate
  = EmitStringTemplate { emitStrParts :: [[EmitStringPart]] }
  deriving (Show)

instance PrettyShow EmitStringTemplate where
  pShow t = intercalate "\n" $
            map pShow $
            emitStrParts t

-- | Represents parts of the emit string template.
data EmitStringPart
    -- | Denotes string which is meant to be output verbatim.
  = ESVerbatim String
    -- | Denotes the integer constant of a given value node.
  | ESIntConstOfValueNode NodeID
    -- | Denotes the location assigned to a given value node.
  | ESLocationOfValueNode NodeID
    -- | Denotes the name a given block node.
  | ESNameOfBlockNode NodeID
    -- | Denotes the block in which the definer of a given value node has been
    -- placed.
  | ESBlockOfValueNode NodeID
    -- | Upon code emission, this will be replaced by a new, uniquely named
    -- temporary. If multiple local temporaries with identical identifiers
    -- appear within the same template, they will all be replaced by the same
    -- temporary.
  | ESLocalTemporary Int
    -- | Denotes the function name of a given call node.
  | ESFuncOfCallNode NodeID
  deriving (Show, Eq)

instance PrettyShow EmitStringPart where
  pShow (ESVerbatim str) = str
  pShow (ESIntConstOfValueNode nid) = "[const of vnode " ++ pShow nid ++ "]"
  pShow (ESLocationOfValueNode nid) = "[loc of vnode " ++ pShow nid ++ "]"
  pShow (ESNameOfBlockNode nid) = "[name of bnode " ++ pShow nid ++ "]"
  pShow (ESBlockOfValueNode nid) = "[block of vnode " ++ pShow nid ++ "]"
  pShow (ESLocalTemporary i) = "%" ++ pShow i
  pShow (ESFuncOfCallNode nid) = "[func of cnode " ++ pShow nid ++ "]"
  pShowList ps = concatMap pShow ps

-- | Defines a machine instruction.
data Instruction
  = Instruction
      { instrID :: InstructionID
        -- ^ The ID of this instruction. The ID must be globally unique across
        -- all instructions, but not necessarily contiguous.
      , instrPatterns :: [InstrPattern]
        -- ^ Patterns which correspond to the instruction. There must be at
        -- least one pattern. Each pattern also has a corresponding ID which
        -- must be globally unique across all patterns and all instructions, but
        -- not necessarily contiguous. It is assumed that there are only a few
        -- patterns per instruction (less than ten), hence it is represented as
        -- a list instead of a map even though it is common to search for a
        -- pattern with a given ID.
      , instrProps :: InstrProperties
        -- ^ Instruction properties.
      }
  deriving (Show)

-- | Contains the various properties of an instruction, such as code size and
-- latency.
data InstrProperties
  = InstrProperties
      { instrCodeSize :: Integer
        -- ^ Instruction code size (in bytes).
      , instrLatency :: Integer
        -- ^ Instruction latency (in cycles).
      , instrIsCopy :: Bool
        -- ^ Whether the instruction represents a copy.
      , instrIsInactive :: Bool
        -- ^ Whether the instruction represents an inactive operation.
      , instrIsNull :: Bool
        -- ^ Whether the instruction is a null instruction, i.e. does not emit
        -- anything during code emission.
      , instrIsPhi :: Bool
        -- ^ Whether the instruction represents an phi operation.
      , instrIsSimd :: Bool
        -- ^ Whether the instruction is a SIMD instruction.
      }
  deriving (Show)

-- | Defines a pattern for a machine instruction.
data InstrPattern
  = InstrPattern
      { patID :: PatternID
        -- ^ The ID of this pattern. The ID must be unique within the same
        -- instruction, but not necessarily contiguous.
      , patOS :: OpStructure
        -- ^ The operation structure of the pattern.
      , patInputData :: [NodeID]
        -- ^ The value nodes in the pattern graph that represent input values of
        -- the instruction.
      , patOutputData :: [NodeID]
        -- ^ The value nodes in the pattern graph that represent output values
        -- of the instruction.
      , patEmitString :: EmitStringTemplate
        -- ^ The emit string from which the assembly instruction will be
        -- produced upon code emission if this pattern is selected.
      }
  deriving (Show)

-- | Represents a target machine.
data TargetMachine
  = TargetMachine
      { tmID :: TargetMachineID
        -- ^ The identifier of the target machine.
      , tmInstructions :: M.Map InstructionID Instruction
        -- ^ The set of assembly instructions supported by the target machine.
        -- It is assumed there are many instructions per target machine (more
        -- than a hundred), hence they are represented as a map because it is
        -- common to search for an instruction with a given ID.
      , tmLocations :: M.Map LocationID Location
        -- ^ The machine locations, given as pairs of location IDs and location
        -- names (which are needed during instruction emission). Each must be
        -- given a unique location ID, but not necessarily in a contiguous
        -- order. It is assumed there are many locations per target machine
        -- (more than a hundred), hence they are represented as a map because it
        -- is common to search for an location with a given ID.
      , tmPointerSize :: Natural
       -- ^ The size (in number of bits) of a memory pointer in the target
       -- macine.
      , tmNullPointerValue :: Integer
       -- ^ The integer value representing a null-pointer in the target machine.
      }
  deriving (Show)

-- | Represents a machine location.
data Location
  = Location
      { locID :: LocationID
        -- ^ The ID of this location. This must be unique for every location
        -- within the same target machine.
      , locName :: LocationName
        -- ^ The name of this location (as it shall appear in the assembly
        -- string).
      , locValue :: Maybe Integer
        -- ^ The fixed value, if any, represented by this location (such as a
        -- register that always contains the value zero).
      }
  deriving (Show, Eq)

instance PrettyShow Location where
  pShow (Location lid name val) = "Location (" ++ pShow lid ++ ", " ++
                                  pShow name ++ ", " ++ pShow val ++ ")"



-------------
-- Functions
-------------

-- | Gets all instructions from a given target machine.
getAllInstructions :: TargetMachine -> [Instruction]
getAllInstructions = M.elems . tmInstructions

-- | Replaces all instructions in a given target machine.
replaceAllInstructions :: [Instruction] -> TargetMachine -> TargetMachine
replaceAllInstructions is tm = tm { tmInstructions = M.fromList $
                                                     zip (map instrID is) is
                                  }

-- | Finds an instruction with a given ID within the given target machine. If no
-- such instruction is found, 'Nothing' is returned.
findInstruction :: TargetMachine -> InstructionID -> Maybe Instruction
findInstruction tm iid = M.lookup iid (tmInstructions tm)

-- | Given a list of instruction patterns, the function finds the 'InstrPattern'
-- entity with matching pattern ID. If there is more than one match, the first
-- found is returned. If no such entity is found, 'Nothing' is returned.
findInstrPattern :: [InstrPattern] -> PatternID -> Maybe InstrPattern
findInstrPattern ps pid =
  let found = filter (\p -> patID p == pid) ps
  in if length found > 0
     then Just $ head found
     else Nothing

-- | Gets all locations from a given target machine.
getAllLocations :: TargetMachine -> [Location]
getAllLocations = M.elems . tmLocations

-- | Replaces all locations in a given target machine.
replaceAllLocations :: [Location] -> TargetMachine -> TargetMachine
replaceAllLocations ls tm = tm { tmLocations = M.fromList $
                                               zip (map locID ls) ls
                               }

-- | Finds an location with a given ID within the given target machine. If no
-- such location is found, 'Nothing' is returned.
findLocation :: TargetMachine -> LocationID -> Maybe Location
findLocation tm iid = M.lookup iid (tmLocations tm)

-- | Replaces a node reference used in the template with another reference.
updateNodeInEmitStrTemplate
  :: NodeID
     -- ^ The new node ID.
  -> NodeID
     -- ^ The old node ID to be replaced.
  -> EmitStringTemplate
  -> EmitStringTemplate
updateNodeInEmitStrTemplate new_n old_n (EmitStringTemplate ts) =
  EmitStringTemplate $ map (map update) ts
  where update (ESIntConstOfValueNode n) =
          ESIntConstOfValueNode (checkAndReplace n)
        update (ESLocationOfValueNode n) =
          ESLocationOfValueNode (checkAndReplace n)
        update (ESNameOfBlockNode n) = ESNameOfBlockNode (checkAndReplace n)
        update (ESBlockOfValueNode n) = ESBlockOfValueNode (checkAndReplace n)
        update p = p
        checkAndReplace nid = if nid == old_n then new_n else nid

-- | Checks whether the instruction is a null instruction.
isInstructionNull :: Instruction -> Bool
isInstructionNull = instrIsNull . instrProps

-- | Checks whether the instruction is a copy instruction.
isInstructionCopy :: Instruction -> Bool
isInstructionCopy = instrIsCopy . instrProps

-- | Checks whether the instruction is an inactive instruction.
isInstructionInactive :: Instruction -> Bool
isInstructionInactive = instrIsInactive . instrProps

-- | Checks whether the instruction is a phi instruction.
isInstructionPhi :: Instruction -> Bool
isInstructionPhi = instrIsPhi . instrProps

-- | Checks whether the instruction is a SIMD instruction.
isInstructionSimd :: Instruction -> Bool
isInstructionSimd = instrIsSimd . instrProps

-- | Concatenates one emit string to another.
concatEmitStrings ::
  EmitStringTemplate ->
  EmitStringTemplate ->
  EmitStringTemplate
concatEmitStrings str1 str2 =
  EmitStringTemplate { emitStrParts = emitStrParts str1 ++ emitStrParts str2 }
