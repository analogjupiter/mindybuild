/+
	This file is part of «mindybuild» — “an open-source build configuration and build system.”
	Copyright © 2026  Mindy Batek (0xEAB)

	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at https://mozilla.org/MPL/2.0/.
 +/
/++
	libkapenparse — A very very limited D parser for the purpose of extracting package and module names.
 +/
module mindybuild.kapenparse;

alias str = const(char)[];

///
const(str)[] parseModuleName(str sourceCode) @safe pure {
	import std.array;

	alias Type = Token.Type;

	auto result = appender!(const(str)[]);

	auto lexer = Lexer(sourceCode);
	if (lexer.empty) {
		return null;
	}

	if (lexer.front.type == Type.hashBangLine) {
		lexer.popFront();
	}

	while (!lexer.empty) {
		if (lexer.front.type == Type.somethingElse) {
			return null;
		}

		if (lexer.front.type == Type.module_) {
			lexer.popFront();
			if (lexer.isEmptyOrEOF) {
				throw new ParserException("Unexpected end of file.");
			}

			while (true) {
				lexer.popWhitespace();
				if (lexer.isEmptyOrEOF) {
					throw new ParserException("Unexpected end of file; identifier expected.");
				}

				if (lexer.front.type != Type.indentifier) {
					throw new ParserException("Unexpected token; identifier expected.");
				}

				result ~= lexer.front.data;

				lexer.popFront();
				lexer.popWhitespace();
				if (lexer.isEmptyOrEOF) {
					throw new ParserException("Unexpected end of file; dot, semicolon or edition identifier expected.");
				}

				if (lexer.front.type == Type.semicolon) {
					return result[];
				}

				// edition identifier?
				if (lexer.front.type == Type.literalInteger) {
					lexer.popFront();
					lexer.popWhitespace();
					if (lexer.isEmptyOrEOF) {
						throw new ParserException("Unexpected end of file; semicolon expected.");
					}
					if (lexer.front.type != Type.semicolon) {
						throw new ParserException("Unexpected token; semicolon expected.");
					}

					return result[];
				}

				if (lexer.front.type != Type.dot) {
					throw new ParserException("Unexpected token; dot, semicolon or edition identifier expected.");
				}

				lexer.popFront();
			}
		}

		lexer.popFront();
	}

	throw new ParserException("Unexpected end of file.");
}

final class ParserException : Exception {
	private this(string message, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow @nogc {
		super(message, file, line);
	}
}

struct Token {
	enum Type : char {
		invalid = '\0',
		comment = '/',
		whitespace = ' ',
		deprecated_ = 'd',
		module_ = 'm',
		indentifier = 'i',
		dot = '.',
		colon = ':',
		semicolon = ';',
		hashBangLine = '#',
		braceParenOpen = '(',
		braceParenClose = ')',
		at = '@',
		literalInteger = '1',
		literalString = '"',
		somethingElse = '?',
		eol = '\n',
		eof = char.max,
	}

	Type type;
	str data;
}

struct Lexer {
	import std.uni;

	private {
		alias Type = Token.Type;

		str _input = null;
		Token _front;
	}

@safe pure nothrow @nogc:

	public this(str input) {
		_input = input;
		this.skipBOM();
		this.loadFront();
	}

	public {

		bool empty() const {
			return _input is null;
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

		Token makeToken(Type type, size_t length) {
			const data = _input[0 .. length];
			_input = _input[length .. $];
			return Token(type, data);
		}

		Token lexToken() {
			if (_input.length == 0) {
				return Token(Type.eof, null);
			}

			switch (_input[0]) {
			case ' ':
				return this.lexWhitespace();

			case 'a': .. case 'z':
			case 'A': .. case 'Z':
			case '_':
				return this.lexIdentifierOrKeyword();

			case '0': .. case '9':
				return this.lexLiteralInteger();

			case '.':
				return this.makeToken(Type.dot, 1);

			case ';':
				return this.makeToken(Type.semicolon, 1);

			case ':':
				return this.makeToken(Type.colon, 1);

			case '/':
				return this.lexSlash();

			case '#':
				return this.lexHash();

			case '@':
				return this.makeToken(Type.at, 1);

			case '(':
				return this.makeToken(Type.braceParenOpen, 1);
			case ')':
				return this.makeToken(Type.braceParenClose, 1);

			case '"':
				return this.lexLiteralString();

			case '\\':
				return this.lexIdentifierOrKeyword();

			case '\x0A':
			case '\x0D':
			case '\xE2':
				return this.lexLinebreak();

			default:
				return this.lexIdentifierOrKeyword();
			}
		}

		ptrdiff_t scanIdentifier() {
			auto data = _input;
			auto idx = 0;
			while (data.length > 0) {
				const c = data[0];

				if (c == '\\') {
					const ucn = this.scanUniversalCharacterName(idx);
					if (ucn < 0) {
						return -1;
					}
					data = data[ucn .. $];
					idx += ucn;
					continue;
				}

				const bool isEnd = !(
					c.isAlphaNum || c == '_'
				);

				if (isEnd) {
					return idx;
				}

				data = data[1 .. $];
				++idx;
			}

			return _input.length;
		}

		ptrdiff_t scanUniversalCharacterName(size_t offset) {
			import std.ascii : isHexDigit;

			const data = _input[offset .. $];
			if (data.length < 2) {
				return -1;
			}

			if (data[1] == 'u') {
				if (data.length < (2 + 4)) {
					return -1;
				}

				foreach (c; data[2 .. 2 + 4]) {
					if (!c.isHexDigit) {
						return -1;
					}
				}

				return 4;
			}

			if (data[1] == 'U') {
				if (data.length < (2 + 8)) {
					return -1;
				}

				foreach (c; data[2 .. 2 + 8]) {
					if (!c.isHexDigit) {
						return -1;
					}
				}

				return 8;
			}

			return -1;
		}

		Token lexIdentifierOrKeyword() {
			const length = this.scanIdentifier();
			if (length < 0) {
				return this.makeToken(Type.invalid, _input.length);
			}

			if (length == 0) {
				return this.makeToken(Type.somethingElse, 1);
			}

			if (_input[1] == '"') {
				return this.lexLiteralString();
			}

			const id = _input[0 .. length];
			switch (id) {
			case "module":
				return this.makeToken(Type.module_, length);

			case "import":
				return this.makeToken(Type.somethingElse, length);

			case "alias":
			case "class":
			case "enum":
			case "package":
			case "private":
			case "protected":
			case "public":
			case "struct":
			case "void":
				goto case "import";

			default:
				break;
			}

			return this.makeToken(Type.indentifier, length);
		}

		Token lexWhitespace() {
			static ptrdiff_t findNonWhitespace(str data) {
				foreach (idx, c; data) {
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

			const idx = findNonWhitespace(_input[1 .. $]);
			const length = (idx < 0) ? _input.length : 1 + idx;
			return this.makeToken(Type.whitespace, length);
		}

		Token lexSlash() {
			if (_input.length == 1) {
				return this.makeToken(Type.somethingElse, 1);
			}

			switch (_input[1]) {
			case '/':
				return this.lexLineComment();
			case '+':
				return this.lexNestableComment();
			case '*':
				return this.lexAsteriskComment();

			case '=':
				return this.makeToken(Type.somethingElse, 2);

			default:
				return this.makeToken(Type.somethingElse, 1);
			}
		}

		Token lexLineComment() {
			if (_input.length == 2) {
				return this.makeToken(Type.comment, 2);
			}

			const idxEOL = this.scanEOL();
			const length = (idxEOL < 0) ? _input.length : idxEOL;
			return this.makeToken(Type.comment, length);
		}

		Token lexAsteriskComment() {
			if (_input.length == 2) {
				return this.makeToken(Type.comment, 2);
			}

			bool prevWasAsterisk = false;
			foreach (idx, c; _input[2 .. $]) {
				if (prevWasAsterisk && (c == '/')) {
					return this.makeToken(Type.comment, (2 + idx + 1));
				}
				prevWasAsterisk = (c == '*');
			}

			return this.makeToken(Type.comment, _input.length);
		}

		Token lexNestableComment() {
			if (_input.length == 2) {
				return this.makeToken(Type.comment, 2);
			}

			size_t level = 1;

			bool prevWasPlus = false;
			bool prevWasSlash = false;
			foreach (idx, c; _input[2 .. $]) {
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
					return this.makeToken(Type.comment, (2 + idx + 1));
				}

				prevWasPlus = isPlus;
				prevWasSlash = isSlash;
			}

			return this.makeToken(Type.comment, _input.length);
		}

		Token lexLinebreak() {
			const length = this.startsWithEOL(_input);
			if (length <= 0) {
				return this.makeToken(Type.somethingElse, 1);
			}

			return this.makeToken(Type.eol, length);
		}

		Token lexLiteralInteger() {
			import std.ascii : isDigit, isHexDigit;

			if (_input[0] == '0') {
				if (_input.length < 2) {
					return this.makeToken(Type.literalInteger, 1);
				}

				if (_input[1] == 'x') {
					foreach (idx, c; _input[2 .. $]) {
						const isOther = !(c.isHexDigit || c == '_');
						if (isOther) {
							return this.makeToken(Type.literalInteger, 2 + idx);
						}
					}
				}
				if (_input[1] == 'b') {
					foreach (idx, c; _input[2 .. $]) {
						const isOther = !(c == '1' || c == '0' || c == '_');
						if (isOther) {
							return this.makeToken(Type.literalInteger, 2 + idx);
						}
					}
				}
				if (_input[1] == 'o') {
					foreach (idx, c; _input[2 .. $]) {
						const isOther = !((c >= '0' && c <= '9') || c == '_');
						if (isOther) {
							return this.makeToken(Type.literalInteger, 2 + idx);
						}
					}
				}
			}

			foreach (idx, c; _input) {
				const isOther = !(c.isDigit || c == '_');
				if (isOther) {
					return this.makeToken(Type.literalInteger, idx);
				}
			}

			return this.makeToken(Type.literalInteger, _input.length);
		}

		Token lexLiteralString() {
			static ptrdiff_t scanForClosingDoubleQuote(str input) {
				bool prevWasBackslash = false;
				foreach (idx, c; input) {
					if (prevWasBackslash) {
						prevWasBackslash = false;
						continue;
					}
					else {
						if ((c == '"') && !prevWasBackslash) {
							return idx;
						}

						prevWasBackslash = (c == '\\');
					}
				}

				return -1;
			}

			static ptrdiff_t scanForClosingDoubleQuoteR(str input) {
				foreach (idx, c; input) {
					if (c == '"') {
						return idx;
					}
				}

				return -1;
			}

			static ptrdiff_t scanForClosingBacktick(str input) {
				foreach (idx, c; input) {
					if (c == '`') {
						return idx;
					}
				}

				return -1;
			}

			static ptrdiff_t scanForClosingCurlyBrace(str input) {
				size_t level = 1;
				foreach (idx, c; input) {
					if (c == '{') {
						++level;
					}
					if (c == '}') {
						--level;
						if (level == 0) {
							return idx;
						}
					}
				}

				return -1;
			}

			if (_input.length < 2) {
				return this.makeToken(Type.invalid, _input.length);
			}

			if (_input[0] == '"') {
				const idxEnd = scanForClosingDoubleQuote(_input[1 .. $]);
				const length = (idxEnd < 0) ? _input.length : (1 + idxEnd + 1);
				return this.makeToken(Type.literalString, length);
			}

			if (_input[0] == 'r' && _input[1] == '"') {
				const idxEnd = scanForClosingDoubleQuoteR(_input[2 .. $]);
				const length = (idxEnd < 0) ? _input.length : (2 + idxEnd + 1);
				return this.makeToken(Type.literalString, length);
			}

			if (_input[0] == '`') {
				const idxEnd = scanForClosingBacktick(_input[2 .. $]);
				const length = (idxEnd < 0) ? _input.length : (2 + idxEnd + 1);
				return this.makeToken(Type.literalString, length);
			}

			if (_input[0] == 'q' && _input[1] == '{') {
				const idxEnd = scanForClosingCurlyBrace(_input[2 .. $]);
				const length = (idxEnd < 0) ? _input.length : (2 + idxEnd + 1);
				return this.makeToken(Type.literalString, length);
			}

			return this.makeToken(Type.invalid, _input.length);
		}

		Token lexHash() {
			if (_input.length < 2) {
				return this.makeToken(Type.invalid, 1);
			}

			const type = (_input[1] == '!') ? Type.hashBangLine : Type.somethingElse;
			const idxEOL = this.scanEOL();
			if (idxEOL < 0) {
				return this.makeToken(type, _input.length);
			}

			return this.makeToken(type, idxEOL);
		}

		ptrdiff_t scanEOL() {
			foreach (idx, c; _input) {
				const length = this.startsWithEOL(_input[idx .. $]);
				if (length >= 1) {
					return idx;
				}
			}

			return -1;
		}

		static ptrdiff_t startsWithEOL(str s) {
			if (s.length == 0) {
				return 0;
			}

			switch (s[0]) {
			case '\x0D':
				return ((s.length >= 2) && (s[1] == '\x0A')) ? 2 : 1;

			case '\x0A':
				return 1;

			case '\xE2':
				if (s.length < 3) {
					return 0;
				}
				if (s[1] == '\x80' && (s[2] == '\xA8' || s[2] == '\xA9')) {
					return 3;
				}
				return 0;

			default:
				break;
			}

			return -1;
		}

		void skipBOM() {
			if (_input.length >= 3) {
				if (_input[0 .. 3] == "\xEF\xBB\xBF") {
					_input = _input[3 .. $];
				}
			}
		}
	}
}

private void popWhitespace(ref Lexer lexer) @safe pure nothrow @nogc {
	while (!lexer.empty) {
		if (lexer._front.type != Token.Type.whitespace) {
			return;
		}

		lexer.popFront();
	}
}

private bool isEmptyOrEOF(ref const(Lexer) lexer) @safe pure nothrow @nogc {
	if (lexer.empty) {
		return true;
	}

	return (lexer.front.type == Token.Type.eof);
}

version (KapenparseModuleFinderApp) {
	private int main(string[] args) @system {
		import std.file;
		import std.stdio;

		string[] files = (args.length < 2) ? null : args[1 .. $];

		if (files.length < 1) {
			stderr.writeln("Error: No input files provided.");
			return 1;
		}

		foreach (file; files) {
			const sourceCode = readText(file);
			const(str)[] moduleName;
			try {
				moduleName = parseModuleName(sourceCode);
			}
			catch (ParserException ex) {
				stderr.writeln(ex.message);
				continue;
			}

			foreach (idx, id; moduleName) {
				if (idx == 0) {
					stdout.write(id);
					continue;
				}

				stdout.write(".", id);
			}
			stdout.writeln();
		}

		return 0;
	}
}
