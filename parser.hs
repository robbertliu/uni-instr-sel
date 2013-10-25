{-
Copyright (c) 2013, Gabriel Hjort Blindell <ghb@kth.se>
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-}

{-
Parses a file of S-expressions containing a set of instruction patterns
expressed as LLVM IR statements. The LLVM IR statements of each instruction is
then transformed into a corresponding DAG and then output as S-expressions.
-}

import qualified Language.InstructionSelection.Patterns.LLVM as LLVM
import Language.InstructionSelection.Patterns.LLVM.OSMaker
import Language.InstructionSelection.Patterns.LLVM.SExprParser
import qualified Language.InstructionSelection.Patterns as IntP
import Language.InstructionSelection.Graphs
import Language.InstructionSelection.SExpressions
import Language.InstructionSelection.OperationStructures
import Control.Monad
import System.Exit
import Data.GraphViz hiding (parse)
import Data.GraphViz.Commands.IO

isLeft (Left _) = True
isLeft _ = False

getPatterns (LLVM.Instruction _ pats) = pats
getGr (Graph g) = g

main =
  do contents <- getContents
     putStr "\n"
     let result = parse contents
     when (isLeft result) $ do let (Left error) = result
                               putStr $ show error
                               exitFailure

     let (Right instructions) = result
         llvm_patterns = concat $ map getPatterns instructions
         int_patterns = map mkOpStructure llvm_patterns
         dots = map (graphToDot params . getGr . graph) int_patterns
     mapM_ (writeDotFile "test.dot") dots
     putStr "\n"

params = nonClusteredParams { fmtNode = nodeAttr }
nodeAttr n@(_, (NodeLabel _ (NodeInfo NTRegister _ str))) =
  [makeLabel n, shape BoxShape]
nodeAttr n@(_, (NodeLabel _ (NodeInfo NTConstant _ str))) =
  [makeLabel n, shape BoxShape]
nodeAttr n@(_, (NodeLabel _ (NodeInfo _ label str))) = [makeLabel n]
makeLabel (_, (NodeLabel _ (NodeInfo _ (BBLabel l) str))) =
  toLabel (l ++ ":" ++ str)