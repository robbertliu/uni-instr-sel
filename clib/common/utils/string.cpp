/*
 *  Main authors:
 *    Gabriel Hjort Blindell <ghb@kth.se>
 *
 *  Copyright (c) 2012-2016, Gabriel Hjort Blindell <ghb@kth.se>
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *  3. Neither the name of the copyright holder nor the names of its
 *     contributors may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 *  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 *  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER AB BE LIABLE FOR ANY
 *  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 *  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 *  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 *  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "string.h"
#include "../exceptions/exception.h"

using std::list;
using std::string;
using std::stringstream;
using std::vector;

namespace Utils {

bool
isWhitespace(char c) {
    switch (c) {
        case ' ':
        case '\n':
        case '\r':
        case '\t':
        case '\v':
        case '\f':
            return true;

        default:
            return false;
    }
}

bool
isNumeric(char c) {
    switch (c) {
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
            return true;

        default:
            return false;
    }
}

bool
isNumeric(const string& str) {
    if (str.length() == 0) return false;

    size_t pos = 0;
    if (str[0] == '-') pos++;
    if (pos == str.length() || !isNumeric(str[pos++])) return false;
    while (pos < str.length()) {
        if (!isNumeric(str[pos++])) return false;
    }
    return true;
}

int
toInt(const string& str) {
    if (!isNumeric(str)) THROW(Exception, "Not a number");
    return stoi(str);
}

string
searchReplace(
    const string& str,
    const string& search,
    const string& replace
) {
    string new_str(str);
    size_t pos = 0;
    while ((pos = new_str.find(search, pos)) != string::npos) {
        new_str.replace(pos, search.length(), replace);
        pos += replace.length();
    }
    return new_str;
}

string
join(const list<string>& strs,
     const string& delim
) {
    if (strs.size() == 0) return "";

    stringstream joined;
    bool is_first = true;
    for (auto& str : strs) {
        if (!is_first) joined << delim;
        else is_first = false;
        joined << str;
    }
    return joined.str();
}

string
join(const vector<string>& strs,
     const string& delim
) {
    if (strs.size() == 0) return "";

    stringstream joined;
    bool is_first = true;
    for (auto& str : strs) {
        if (!is_first) joined << delim;
        else is_first = false;
        joined << str;
    }
    return joined.str();
}

}
