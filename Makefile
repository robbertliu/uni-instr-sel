#
#  Main authors:
#    Gabriel Hjort Blindell <ghb@kth.se>
#
#  Copyright (c) 2012-2016, Gabriel Hjort Blindell <ghb@kth.se>
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#  1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#  3. Neither the name of the copyright holder nor the names of its contributors
#     may be used to endorse or promote products derived from this software
#     without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
#  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#



#==========
# SETTINGS
#==========

HLIB_PATH       := hlib/instr-sel
UNI_IS_PATH     := uni-is
UNI_TARGEN_PATH := uni-targen
SOLVERS_PATH    := solvers
TOOLS_PATH      := tools



#=======
# RULES
#=======

.PHONY: build
build: hlib uni-is uni-targen

.PHONY: docs
docs: hlib uni-is-doc uni-targen-doc

.PHONY: hlib
hlib:
	cd $(HLIB_PATH) && make

.PHONY: hlib-doc
hlib-doc:
	cd $(HLIB_PATH) && make docs

.PHONY: uni-is
uni-is: hlib
	cd $(UNI_IS_PATH) && make
	cd $(SOLVERS_PATH) && make
	cd $(TOOLS_PATH) && make

.PHONY: uni-is-doc
uni-is-doc:
	cd $(UNI_IS_PATH) && make docs

.PHONY: uni-targen
uni-targen: hlib
	cd $(UNI_TARGEN_PATH) && make

.PHONY: uni-targen-doc
uni-targen-doc:
	cd $(UNI_TARGEN_PATH) && make docs

.PHONY: clean
clean:
	cd $(HLIB_PATH) && make clean
	cd $(UNI_IS_PATH) && make clean
	cd $(UNI_TARGEN_PATH) && make clean
	cd $(SOLVERS_PATH) && make clean
	cd $(TOOLS_PATH) && make clean

.PHONY: distclean
distclean:
	cd $(HLIB_PATH) && make distclean
	cd $(UNI_IS_PATH) && make distclean
	cd $(UNI_TARGEN_PATH) && make distclean
	cd $(SOLVERS_PATH) && make distclean
	cd $(TOOLS_PATH) && make distclean
