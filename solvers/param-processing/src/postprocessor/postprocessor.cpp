/**
 * Copyright (c) 2014, Gabriel Hjort Blindell <ghb@kth.se>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include "../common/constraintprocessor.h"
#include "../common/preparams.h"
#include "../../../common/exceptions/exception.h"
#include "../../../common/model/types.h"
#include "../../../common/optionparser/optionparser.h"
#include <fstream>
#include <iostream>
#include <list>
#include <sstream>
#include <string>
#include <vector>

using namespace Model;
using std::cerr;
using std::cout;
using std::endl;
using std::ifstream;
using std::list;
using std::ofstream;
using std::ostream;
using std::string;
using std::stringstream;
using std::vector;



//================
// HELP FUNCTIONS
//================

template <typename T>
void
printJsonList(ostream&, const T&);

template <typename T>
void
printJsonValue(ostream& out, const list<T>& l) {
    printJsonList(out, l);
}

template <typename T>
void
printJsonValue(ostream& out, const vector<T>& v) {
    printJsonList(out, v);
}

template <typename T>
void
printJsonValue(ostream& out, const T& v) {
    out << v;
}

template <>
void
printJsonValue(ostream& out, const bool& v) {
    out << (v ? "true" : "false");
}

template <typename T>
void
printJsonList(ostream& out, const T& l) {
    out << "[";
    bool isFirst = true;
    for (const auto& e : l) {
        if (isFirst) isFirst = false;
        else out << ",";
        printJsonValue(out, e);
    }
    out << "]";
}



//======================
// COMMAND-LINE OPTIONS
//======================

enum optionIndex {
    PRE,
    HELP,
    SF,
    PPF
};

const option::Descriptor usage[] =
{
    {
        PRE,
        0,
        "",
        "",
        option::Arg::None,
        "USAGE: input-gen [OPTIONS] INPUTFILE\n" \
        "Options:"
    },
    {
        HELP,
        0,
        "h",
        "help",
        option::Arg::None,
        "  -h, --help\n" \
        "\tPrints this menu."
    },
    {
        SF,
        0,
        "",
        "sf",
        option::Arg::Required,
        "  --spf=FILE\n" \
        "\tJSON file containing the solution."
    },
    {
        PPF,
        0,
        "",
        "ppf",
        option::Arg::Required,
        "  --ppf=FILE\n" \
        "\tJSON file containing the post-processing parameters."
    },
    // Termination sentinel
    { 0, 0, 0, 0, 0, 0 }
};

int
main(int argc, char** argv) {
    // Parse command-line arguments
    argc -= (argc > 0); argv += (argc > 0); // Skip program name if present
    option::Stats stats(usage, argc, argv);
    option::Option options[stats.options_max], buffer[stats.buffer_max];
    option::Parser cmdparser(usage, argc, argv, options, buffer);
    if (cmdparser.error()) {
        return 1;
    }
    if (options[HELP] || argc == 0) {
        option::printUsage(cout, usage);
        return 0;
    }
    if (!options[SF]) {
        cerr << "No solution file" << endl;
        return 1;
    }
    if (!options[PPF]) {
        cerr << "No post-processing params file" << endl;
        return 1;
    }
    if (cmdparser.nonOptionsCount() >= 1) {
        cerr << "Unknown option '" << cmdparser.nonOption(0) << "'" << endl;
        return 1;
    }

    try {
        // Parse JSON file into an internal model parameters object
        string sol_json_file(options[SF].arg);
        ifstream sfile(sol_json_file);
        if (!sfile.good()) {
            cerr << "ERROR: '" << sol_json_file << "' does not exist or is "
                 << "unreadable" << endl;
            return 1;
        }
        stringstream ss;
        ss << sfile.rdbuf();
        const string sol_json_content(ss.str());
        Preparams params;
        Preparams::parseJson(sol_json_content, params);

        // Output final solution
        // TODO: implement

        return 0;
    }
    catch (Exception& ex) {
        cerr << "ERROR: " << ex.toString() << endl;
        return 1;
    }
}