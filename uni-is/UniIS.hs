{-
Copyright (c) 2014, Gabriel Hjort Blindell <ghb@kth.se>
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

import Language.InstSel.Drivers
import qualified Language.InstSel.Drivers.CheckDispatcher as Check
import qualified Language.InstSel.Drivers.MakeDispatcher as Make
import qualified Language.InstSel.Drivers.PlotDispatcher as Plot
import qualified Language.InstSel.Drivers.TransformDispatcher as Transform

import Language.InstSel.Utils
  ( splitOn
  , toLower
  )

import System.Console.CmdArgs
import System.Console.CmdArgs.Text

import Data.Maybe
  ( fromJust
  , isNothing
  )
import System.FilePath.Posix
  ( splitExtension )



-------------
-- Functions
-------------

parseArgs :: Options
parseArgs =
  Options
    { command = def
        &= argPos 0
        &= typ "COMMAND"
    , functionFile = def
        &= name "f"
        &= name "function-file"
        &= explicit
        &= typFile
        &= help "File containing a function."
    , matchsetFile = def
        &= typFile
        &= explicit
        &= name "m"
        &= name "matchset-file"
        &= help "File containing matchset information."
    , arraysNodesMapFile = def
        &= name "a"
        &= name "arrays-nodes-map-file"
        &= explicit
        &= typFile
        &= help "File containing array-index-to-node-ID mapping information."
    , cpModelFile = def
        &= typFile
        &= explicit
        &= name "c"
        &= name "cp-model-file"
        &= help "File containing a CP model instance."
    , solutionFile = def
        &= name "s"
        &= name "solution-file"
        &= explicit
        &= typFile
        &= help "File containing a CP model solution."
    , outFile = def
        &= name "o"
        &= name "output"
        &= explicit
        &= help ( "File that will contain the output. If the output involves "
                  ++ "multiple files, each file will be suffixed with a "
                  ++ "unique ID."
                )
        &= typFile
    , targetName = def
        &= name "t"
        &= name "target-name"
        &= explicit
        &= typ "TARGET"
        &= help "Name of a target machine."
    , makeAction =
        enum [ MakeNothing
                 &= auto
                 &= ignore
             , MakeFunctionGraphFromLLVM
                 &= name "make-fun-from-llvm"
                 &= explicit
                 &= help "Makes a function from an LLVM IR file."
             , MakeMatchsetInfo
                 &= name "make-matchset"
                 &= explicit
                 &= help ( "Makes the matchset by performing pattern matching "
                           ++ "the given function and target machine."
                         )
             ]
        &= groupname "'make' command flags"
    , transformAction =
        enum [ TransformNothing
                 &= auto
                 &= ignore
             , CopyExtendFunctionGraph
                 &= name "copy-extend-fun"
                 &= explicit
                 &= help "Extends the given function with copies."
             , BranchExtendFunctionGraph
                 &= name "branch-extend-fun"
                 &= explicit
                 &= help ( "Extends the given function with additional "
                           ++ "branches alone every conditional control flow "
                           ++ "edge."
                         )
             ]
        &= groupname "'transform' command flags"
    , plotAction =
        enum [ PlotNothing
                 &= auto
                 &= ignore
             , PlotFunctionGraph
                 &= name "plot-fun-graph"
                 &= explicit
                 &= help "Plots the function graph (in DOT format)."
             , PlotCoverAllMatches
                 &= name "plot-cover-all-matches"
                 &= explicit
                 &= help ( "Same as --plot-fun-graph, but also marks the nodes "
                           ++ "that is potentially covered by some match."
                         )
             , PlotCoverPerMatch
                 &= name "plot-cover-per-match"
                 &= explicit
                 &= help ( "Same as --plot-cover-all-matches, but produces a "
                           ++ "separate plot for each individual match."
                         )
             ]
        &= groupname "'plot' command flags"
    , checkAction =
        enum [ CheckNothing
                 &= auto
                 &= ignore
             ]
        &= groupname "'check' command flags"
    }
    &= helpArg [ help "Displays this message."
               , name "h"
               , name "help"
               , explicit
               , groupname "Other flags"
               ]
    &= versionArg [ ignore ]
    &= program "uni-is"
    &= summary ( "Unison (instruction selection) tool\n"
                 ++
                 "Gabriel Hjort Blindell <ghb@kth.se>"
               )
    &= details
         ( splitOn
             "\n"
             ( showText
                 defaultWrap
                 [ Line "Available commands:"
                 , Cols [ "  make"
                        , "  Produce new data from the input."
                        ]
                 , Cols [ "  transform"
                        , "  Perform a transformation on the input."
                        ]
                 , Cols [ "  plot"
                        , "  Produce various plots for the input."
                        ]
                 , Cols [ "  check"
                        , "  Perform various checks on the input."
                        ]
                 , Line "The commands may be written in lower or upper case."
                 ]
             )
         )

-- | If an output file is given as part of the options, then the returned
-- function will emit all data to the output file with the output ID suffixed to
-- the output file name (this may mean that several output files are
-- produced). Otherwise the data will be emitted to 'STDOUT'.
mkEmitFunction :: Options -> IO (Output -> IO ())
mkEmitFunction opts =
  do let file = outFile opts
     if isNothing file
     then return emitToStdout
     else return $ emitToFile (fromJust file)

-- | A function that emits output to 'STDOUT'.
emitToStdout :: Output -> IO ()
emitToStdout = putStrLn . oData

-- | A function that emits output to a file of a given name and the output ID
-- suffixed.
emitToFile :: FilePath -> Output -> IO ()
emitToFile fp o =
  let (fname, ext) = splitExtension fp
      filename = fname ++ "." ++ oID o ++ ext
  in writeFile filename (oData o)



----------------
-- Main program
----------------

main :: IO ()
main =
  do opts <- cmdArgs parseArgs
     output <-
       case (toLower $ command opts) of
         "make"      -> Make.run opts
         "transform" -> Transform.run opts
         "plot"      -> Plot.run opts
         "check"     -> Check.run opts
         cmd ->
           error $ "Unrecognized command: " ++ show cmd
     emit <- mkEmitFunction opts
     mapM_ emit output
