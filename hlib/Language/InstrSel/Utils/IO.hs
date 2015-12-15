--------------------------------------------------------------------------------
-- |
-- Module      : Language.InstrSel.Utils.IO
-- Copyright   : (c) Gabriel Hjort Blindell 2013-2015
-- License     : BSD-style (see the LICENSE file)
--
-- Maintainer  : ghb@kth.se
-- Stability   : experimental
-- Portability : portable
--
-- Various IO-related functions.
--
--------------------------------------------------------------------------------

module Language.InstrSel.Utils.IO where

import Control.Monad
  ( when )

import qualified System.Directory as D
  ( doesFileExist )

import System.Exit
  ( exitFailure )



-------------
-- Functions
-------------

-- | Reports an error, and then terminates the program with an appropriate exit
-- code.
reportError :: String -> IO a
reportError str =
  do putStrLn str
     exitFailure

-- | Checks if a given file exists.
doesFileExist :: FilePath -> IO Bool
doesFileExist = D.doesFileExist

-- | Reads the content of a given file. If the file does not exist an error is
-- reported and then the program fails.
readFileContent :: FilePath -> IO String
readFileContent file =
  do exists_file <- doesFileExist file
     when (not exists_file) $
       reportError $ "File " ++ show file ++ " does not exist."
     readFile file
