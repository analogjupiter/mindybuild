/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	libAnnaBEL — Implementation of the Build Expression Language.
 +/
module mindybuild.annabel;

alias str = const(char)[];

struct Location {
	size_t byteOffset;
	str file;
	str sourceCode;
}

struct Token {
	enum Type : char {
		invalid = '\x00',

		whitespace = ' ',
		comment = '#',

		comma = ',',
		dot = '.',
		colon = ':',
		semicolon = ';',
		equals = '=',

		braceParenOpen = '(',
		braceParenClose = ')',
		braceSquarOpen = '[',
		braceSquarClose = ']',
		braceCurlyOpen = '{',
		braceCurlyClose = '}',

		opConcat = '~',
		opAppend = 'a',

		identifier = 'i',
		literalString = '"',

		eof = char.max,
	}

	Type type;
	str data;
	Location location;
}

struct Lexer {

	private {
		alias Type = Token.Type;

		str _input = null;
		Location _loc;
		Token _front;
	}

	public this(str input, str file = null) {
		_input = input;
		_loc = Location(0, file, input);
		this.popFront();
	}

	public {
		bool empty() const {
			return (_input is null);
		}

		inout(Token) front() inout {
			return _front;
		}

		void popFront() {
			if (_front.type == Type.eof) {
				_input = null;
				return;
			}

			this.loadFront();
		}
	}

	private {
		void loadFront() {
			_front = lexToken();
		}

		Token makeToken(Token.Type type, size_t length) {
			const data = _input[0 .. length];
			_input = _input[length .. $];
			_loc.byteOffset += length;
			return Token(type, data, _loc);
		}

		Token lexToken() {
			if (_input.length == 0) {
				return Token(Type.eof, null, _loc);
			}

			// byte order mark
			if (_loc.byteOffset == 0) {
				if (_input.length >= 3) {
					if (_input[0 .. 3] == "\xEF\xBB\xBF") {
						_input = _input[3 .. $];
					}
				}
			}

			switch (_input[0]) {
			case '\x20':
			case '\x0A':
			case '\x0B':
			case '\x0C':
			case '\x0D':
				return this.lexWhitespace();

			case '\x80': .. case '\xFF':
			default:
				return this.makeToken(Type.invalid, 1);
			}
		}

		Token lexWhitespace() {
			foreach (idx, c; _input[1 .. $]) {
				switch (c) {
				case '\x20':
				case '\x0A':
				case '\x0B':
				case '\x0C':
				case '\x0D':
					return this.lexWhitespace();

				default:
					return this.makeToken(Type.whitespace, 1 + idx);
				}
			}

			return this.makeToken(Type.whitespace, _input.length);
		}
	}
}
