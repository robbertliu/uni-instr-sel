--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstrSel.OpStructures.Base
-- Copyright   : (c) Gabriel Hjort Blindell 2013-2015
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Contains the data types and functions for representing the operation
-- structures that constitute the input programs and patterns.
--
-- Both constants and immediate symbols are mapped to a constant node on which a
-- 'ConstantValueConstraint' applies to restrict the value. The same goes for
-- temporaries (which will later be allocated to a register) and data nodes
-- whose value must be allocated to a specific register.
--
--------------------------------------------------------------------------------

{-# LANGUAGE OverloadedStrings, FlexibleInstances #-}

module Language.InstrSel.OpStructures.Base
  ( OpStructure (..)
  , addConstraint
  , addConstraints
  , mkEmpty
  )
where

import Language.InstrSel.Constraints
import qualified Language.InstrSel.Graphs as G
  ( Graph
  , NodeID
  , mkEmpty
  )
import Language.InstrSel.Utils.JSON



--------------
-- Data types
--------------

data OpStructure
  = OpStructure
      { osGraph :: G.Graph
      , osEntryLabelNode :: Maybe G.NodeID
      , osConstraints :: [Constraint]
      }
  deriving (Show)



--------------------------
-- JSON-related instances
--------------------------

instance FromJSON OpStructure where
  parseJSON (Object v) =
    OpStructure
      <$> v .: "graph"
      <*> v .: "entry-label-node"
      <*> v .: "constraints"
  parseJSON _ = mzero

instance ToJSON OpStructure where
  toJSON os =
    object [ "graph"            .= (osGraph os)
           , "entry-label-node" .= (osEntryLabelNode os)
           , "constraints"      .= (osConstraints os)
           ]



-------------
-- Functions
-------------

-- | Creates an empty operation structure.
mkEmpty :: OpStructure
mkEmpty = OpStructure { osGraph = G.mkEmpty
                      , osEntryLabelNode = Nothing
                      , osConstraints = []
                      }

addConstraint :: OpStructure -> Constraint -> OpStructure
addConstraint os c = os { osConstraints = osConstraints os ++ [c] }

addConstraints :: OpStructure -> [Constraint] -> OpStructure
addConstraints = foldl addConstraint