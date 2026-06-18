/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	Common library of mindybuild.
 +/
module mindybuild.common;

///
alias str = const(char)[];

///
enum Status : bool {
	///
	error = false,
	///
	success = true,
}

///
bool isOK(const Status status) @safe pure nothrow @nogc {
	return (status == Status.success);
}

///
enum BOM {
	///
	none,
	/// UTF-8
	utf8,
	/// UTF-16 Little Endian
	utf16LE,
	/// UTF-16 Big Endian
	utf16BE,
	/// UTF-32 Little Endian
	utf32LE,
	/// UTF-32 Big Endian
	utf32BE,
}

template bomData(BOM bom) {
	static if (bom == BOM.none) {
		static immutable ubyte[0] bomData = [];
	}
	else static if (bom == BOM.utf8) {
		static immutable ubyte[3] bomData = [0xEF, 0xBB, 0xBF];
	}
	else static if (bom == BOM.utf16LE) {
		static immutable ubyte[2] bomData = [0xFF, 0xFE];
	}
	else static if (bom == BOM.utf16BE) {
		static immutable ubyte[2] bomData = [0xFE, 0xFF];
	}
	else static if (bom == BOM.utf32LE) {
		static immutable ubyte[4] bomData = [0xFF, 0xFE, 0x00, 0x00];
	}
	else static if (bom == BOM.utf32BE) {
		static immutable ubyte[4] bomData = [0x00, 0x00, 0xFE, 0xFF];
	}
	else {
		static assert(false, "Unsupported charset.");
	}
}

///
BOM scanBOM(in str input) @safe pure nothrow @nogc {
	if (input.length >= 4) {
		const firstBytes = input[0 .. 4];
		if (firstBytes == bomData!(BOM.utf32LE)) {
			return BOM.utf32LE;
		}
		if (firstBytes == bomData!(BOM.utf32BE)) {
			return BOM.utf32BE;
		}
	}

	if (input.length >= 3) {
		const firstBytes = input[0 .. 3];
		if (firstBytes == bomData!(BOM.utf8)) {
			return BOM.utf8;
		}
	}

	if (input.length >= 2) {
		const firstBytes = input[0 .. 2];
		if (firstBytes == bomData!(BOM.utf16LE)) {
			return BOM.utf16LE;
		}
		if (firstBytes == bomData!(BOM.utf16BE)) {
			return BOM.utf16BE;
		}
	}

	return BOM.none;
}

/++
	Determines whether a string starts with a line terminator.

	Returns:
		The length of the line terminator, if applicable.
		Otherwise, a negative number.
 +/
ptrdiff_t scanEOL(in str s) @safe pure nothrow @nogc {
	if (s.length == 0) {
		return -1;
	}

	switch (s[0]) {
	case '\x0D':
		return ((s.length >= 2) && (s[1] == '\x0A')) ? 2 : 1;

	case '\x0A':
		return 1;

	case '\xE2':
		if (s.length < 3) {
			return -1;
		}
		if (s[1] == '\x80' && (s[2] == '\xA8' || s[2] == '\xA9')) {
			return 3;
		}
		return -1;

	default:
		break;
	}

	return -1;
}

///
ptrdiff_t indexOfNextEOL(in str input) @safe pure nothrow @nogc {
	foreach (idx, c; input) {
		const length = scanEOL(input[idx .. $]);
		if (length >= 1) {
			return idx;
		}
	}

	return -1;
}

///
ptrdiff_t scanIdentifier(scope str input) @safe pure nothrow @nogc {
	import std.ascii : isAlphaNum;

	auto idx = 0;
	while (input.length > 0) {
		const c = input[0];

		if (c == '\\') {
			const ucn = scanUniversalCharacterName(input);
			if (ucn < 0) {
				return -1;
			}
			input = input[ucn .. $];
			idx += ucn;
			continue;
		}

		if ((ubyte(c) & ubyte(0b1111_0000)) == 0b1111_0000) {
			if (input.length < 4) {
				return -1;
			}
			input = input[4 .. $];
			idx += 4;
			continue;
		}
		if ((ubyte(c) & ubyte(0b1110_0000)) == 0b1110_0000) {
			if (input.length < 3) {
				return -1;
			}

			// EOL?
			if (c == '\xE2' && input[1] == '\x80' && (input[2] == '\xA8' || input[2] == '\xA9')) {
				return idx;
			}

			input = input[3 .. $];
			idx += 3;
			continue;
		}
		if ((ubyte(c) & ubyte(0b1100_0000)) == 0b1100_0000) {
			if (input.length < 2) {
				return -1;
			}
			input = input[2 .. $];
			idx += 2;
			continue;
		}
		if ((ubyte(c) & ubyte(0b1000_0000)) == 0b1000_0000) {
			// bad unicode
			return -1;
		}

		const bool isEnd = !(
			c.isAlphaNum || c == '_'
		);

		if (isEnd) {
			return idx;
		}

		input = input[1 .. $];
		++idx;
	}

	return input.length;
}

///
ptrdiff_t scanUniversalCharacterName(in str input) @safe pure nothrow @nogc {
	import std.ascii : isHexDigit;

	if (input.length < 2) {
		return -1;
	}

	if (input[1] == 'u') {
		if (input.length < (2 + 4)) {
			return -1;
		}

		foreach (c; input[2 .. 2 + 4]) {
			if (!c.isHexDigit) {
				return -1;
			}
		}

		return 4;
	}

	if (input[1] == 'U') {
		if (input.length < (2 + 8)) {
			return -1;
		}

		foreach (c; input[2 .. 2 + 8]) {
			if (!c.isHexDigit) {
				return -1;
			}
		}

		return 8;
	}

	return -1;
}

ptrdiff_t scanLineComment(in str input) @safe pure nothrow @nogc {
	if (input.length < 2 || input[0 .. 2] != "//") {
		return -1;
	}

	if (input.length == 2) {
		return 2;
	}

	const idxEOL = input.indexOfNextEOL();
	const length = (idxEOL < 0) ? input.length : idxEOL;
	return length;
}

ptrdiff_t scanAsteriskComment(in str input) @safe pure nothrow @nogc {
	if (input.length < 2 || input[0 .. 2] != "/*") {
		return -1;
	}

	if (input.length == 2) {
		return 2;
	}

	bool prevWasAsterisk = false;
	foreach (idx, c; input[2 .. $]) {
		if (prevWasAsterisk && (c == '/')) {
			return 2 + idx + 1;
		}
		prevWasAsterisk = (c == '*');
	}

	return input.length;
}

///
ptrdiff_t scanNestableComment(in str input) @safe pure nothrow @nogc {
	if (input.length < 2 || input[0 .. 2] != "/+") {
		return -1;
	}

	if (input.length == 2) {
		return 2;
	}

	size_t level = 1;

	bool prevWasPlus = false;
	bool prevWasSlash = false;
	foreach (idx, c; input[2 .. $]) {
		bool isSlash = (c == '/');
		bool isPlus = false;
		if (prevWasPlus && isSlash) {
			--level;
			isSlash = false;
		}
		else {
			isPlus = (c == '+');
			if (prevWasSlash && isPlus) {
				++level;
				isPlus = false;
			}
		}

		if (level == 0) {
			return 2 + idx + 1;
		}

		prevWasPlus = isPlus;
		prevWasSlash = isSlash;
	}

	return input.length;
}

///
ptrdiff_t scanWhitespace(in str input) @safe pure nothrow @nogc {
	foreach (idx, c; input) {
		switch (c) {
		case '\x20':
		case '\x09':
		case '\x0B':
		case '\x0C':
			continue;

		default:
			return idx;
		}
	}

	return -1;
}

///
struct Location {
	///
	size_t byteOffset;

	///
	str file;

	///
	str sourceCode;
}
