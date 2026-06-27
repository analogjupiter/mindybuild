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

import mindybuild.common;

///
alias Location = mindybuild.common.Location;

///
struct Token {
	///
	enum Type : char {
		invalid = '\x00',

		invalidCharset = '\xFE',

		whitespace = ' ',
		eol = '\n',
		comment = '#',

		comma = ',',
		dot = '.',
		colon = ':',
		semicolon = ';',

		braceParenOpen = '(',
		braceParenClose = ')',
		braceSquarOpen = '[',
		braceSquarClose = ']',
		braceCurlyOpen = '{',
		braceCurlyClose = '}',

		opConcat = '~',
		opAssign = '=',
		opAppend = 'a',

		identifier = 'i',
		literalString = '`',
		literalStringEscaped = '"',

		eof = char.max,
	}

	///
	Type type;

	///
	str data;

	///
	Location location;
}

///
struct Lexer {

	private {
		alias Type = Token.Type;

		str _input = null;
		Location _loc;
		Token _front;
	}

@safe pure nothrow @nogc:

	///
	public this(str input, str file = null) {
		_input = input;
		_loc = Location(file, 0, input);
		this.loadFrontInitial();
	}

	public {
		///
		bool empty() const {
			return (_input is null);
		}

		/++
			Current token of lexed source code.

			Or the final token of an now-empty range;
			i.e. may be called on empty ranges.
		 +/
		inout(Token) front() inout {
			return _front;
		}

		///
		void popFront() {
			if (_front.type == Type.eof) {
				_input = null;
				// keep final token in _front
				return;
			}

			this.loadFront();
		}
	}

	private {
		void loadFrontInitial() {
			const charset = detectAndSkipBOM();
			if (!charset.isOK) {
				_front = this.makeToken(Type.invalidCharset, _input.length);
				return;
			}

			this.loadFront();
		}

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

			switch (_input[0]) {
			case '\x20':
			case '\x09':
			case '\x0B':
			case '\x0C':
				return this.lexWhitespace();

			case '\x0A':
			case '\x0D':
			case '\xE2':
				return this.lexEOL();

			case '"':
			case '`':
				return this.lexLiteralString();

			case '#':
				return this.lexHash();

			case '(':
				return this.makeToken(Type.braceParenOpen, 1);
			case ')':
				return this.makeToken(Type.braceParenClose, 1);
			case '[':
				return this.makeToken(Type.braceSquarOpen, 1);
			case ']':
				return this.makeToken(Type.braceSquarClose, 1);
			case '{':
				return this.makeToken(Type.braceCurlyOpen, 1);
			case '}':
				return this.makeToken(Type.braceCurlyClose, 1);

			case '=':
				return this.makeToken(Type.opAssign, 1);

			case ',':
				return this.makeToken(Type.comma, 1);

			case '.':
				return this.makeToken(Type.dot, 1);

			case '/':
				return this.lexSlash();

			case ':':
				return this.makeToken(Type.colon, 1);

			case ';':
				return this.makeToken(Type.semicolon, 1);

			case '~':
				return this.lexTilde();

			case '\x01': .. case '\x08':
			case '\x0E': .. case '\x1F':
			case '\x7F':
				return this.makeToken(Type.invalid, 1);

			default:
				return this.lexIdentifier();
			}
		}

		Token lexWhitespace() {
			const idx = scanWhitespace(_input[1 .. $]);
			const length = (idx < 0) ? _input.length : 1 + idx;
			return this.makeToken(Type.whitespace, length);
		}

		Token lexIdentifier() {
			const length = scanIdentifier(_input);
			if (length < 0) {
				return this.makeToken(Type.invalid, 1);
			}

			if (length == 0) {
				return this.makeToken(Type.invalid, 1);
			}

			return this.makeToken(Type.identifier, length);
		}

		Token lexEOL() {
			const length = scanEOL(_input);
			if (length <= 0) {
				return this.lexIdentifier();
			}

			return this.makeToken(Type.eol, length);
		}

		Token lexLiteralString() {
			ptrdiff_t scanForClosingDoubleQuote(str input, out bool hasEscapeSequences) {
				hasEscapeSequences = false;
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
						if (prevWasBackslash) {
							hasEscapeSequences = true;
						}
					}
				}
				return -1;
			}

			ptrdiff_t scanForClosingBacktick(str input) {
				foreach (idx, c; input) {
					if (c == '`') {
						return idx;
					}
				}
				return -1;
			}

			if (_input.length < 2) {
				return this.makeToken(Type.invalid, _input.length);
			}

			if (_input[0] == '"') {
				bool hasEscapeSequences;
				const idxEnd = scanForClosingDoubleQuote(_input[1 .. $], hasEscapeSequences);
				const length = (idxEnd < 0) ? _input.length : (1 + idxEnd + 1);
				const stringType = (hasEscapeSequences) ? Type.literalStringEscaped : Type.literalString;
				return this.makeToken(stringType, length);
			}

			if (_input[0] == '`') {
				const idxEnd = scanForClosingBacktick(_input[2 .. $]);
				const length = (idxEnd < 0) ? _input.length : (2 + idxEnd + 1);
				return this.makeToken(Type.literalString, length);
			}

			return this.makeToken(Type.invalid, _input.length);
		}

		Token lexSlash() {
			if (_input.length == 1) {
				return this.makeToken(Type.invalid, 1);
			}

			switch (_input[1]) {
			case '/':
				const length = scanLineComment(_input);
				assert(length >= 0);
				return this.makeToken(Type.comment, length);

			case '+':
				const length = scanNestableComment(_input);
				assert(length >= 0);
				return this.makeToken(Type.comment, length);

			case '*':
				const length = scanAsteriskComment(_input);
				assert(length >= 0);
				return this.makeToken(Type.comment, length);

			default:
				return this.makeToken(Type.invalid, 1);
			}
		}

		Token lexHash() {
			const idxEnd = scanEOL(_input);
			const length = (idxEnd < 0) ? _input.length : idxEnd;
			return this.makeToken(Type.comment, length);
		}

		Token lexTilde() {
			if (_input.length > 1 && _input[1] == '=') {
				return this.makeToken(Type.opAppend, 2);
			}

			return this.makeToken(Type.opConcat, 1);
		}

		Status detectAndSkipBOM() {
			const bom = scanBOM(_input);

			if (bom == BOM.utf8) {
				_input = _input[0 .. bomData!(BOM.utf8).length];
				return Status.success;
			}
			if (bom == BOM.none) {
				return Status.success;
			}

			return Status.error;
		}
	}
}

private struct Feeder {
	import std.meta;

	private {
		alias toSkip = AliasSeq!(
			Token.Type.comment,
			Token.Type.eol,
			Token.Type.eof,
			Token.Type.whitespace,
		);

		Lexer _lexer;
	}

@safe pure nothrow @nogc:

	///
	public this(Lexer lexer) {
		_lexer = lexer;
		this.runSkip();
	}

	public {
		///
		bool empty() const {
			return _lexer.empty;
		}

		/++
			Current token of the filtered lexer output.

			Or the final token of an now-empty range;
			i.e. may be called on empty ranges.
		 +/
		inout(Token) front() inout {
			return _lexer.front;
		}

		///
		void popFront() {
			_lexer.popFront();
			this.runSkip();
		}
	}

	private {
		void runSkip() {
			while (!_lexer.empty) {
				if (!this.shallSkip()) {
					return;
				}
			}
		}

		bool shallSkip() {
			pragma(inline, true);
			// dfmt off
			switch (_lexer.front.type) {
					default:
						return false;

				static foreach (type; toSkip) {
					case type:
						_lexer.popFront();
						return true;
				}
			}
			// dfmt on
		}
	}
}

///
struct Parser {
	private {
		Feeder _feeder;
		Statement _front;
		bool _empty = true;
	}

@safe pure:

	///
	public this(str sourceCode, str file = null) nothrow @nogc {
		auto lexer = Lexer(sourceCode, file);
		this(lexer);
	}

	///
	public this(Lexer lexer) nothrow @nogc {
		auto feeder = Feeder(lexer);
		this(feeder);
	}

	private this(Feeder feeder) nothrow @nogc {
		_feeder = feeder;
		_empty = false;
	}

	public {
		///
		bool empty() const nothrow @nogc {
			return _empty;
		}

		///
		inout(Statement) front() inout nothrow @nogc {
			return _front;
		}

		///
		void popFront() {
			if (_feeder.empty) {
				_empty = true;
				return;
			}

			_front = parseStatement(_feeder);
		}
	}
}

///
class ParserException : Exception {
	public {
		///
		Location location;
	}

	private this(
		string message,
		Location location,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow @nogc {
		this.location = location;
		super(message, file, line);
	}
}

///
final class DuplicateObjectPropertyNameException : ParserException {
	public {
		///
		str propertyName;
	}

	private this(
		str propertyName,
		Location location,
		string file = __FILE__, size_t line = __LINE__) @safe pure {
		import std.conv : text;

		this.propertyName = propertyName;
		super(text("Duplicate property name `", propertyName, "` in object."), location, file, line);

	}
}

///
final class UnexpectedEOFException : ParserException {
	private this(
		Location location,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure nothrow @nogc {
		super("Unexpected end of file.", location, file, line);
	}
}

///
final class UnexpectedTokenException : ParserException {
	public {
		///
		Token got;

		///
		Token.Type[] expected;
	}

	private this(
		Token got,
		Token.Type[] expected,
		string file = __FILE__, size_t line = __LINE__
	) @safe pure
	in (expected.length > 0) {

		string msg() {
			import std.algorithm : map;
			import std.conv : to;
			import std.string : join;

			return "Unexpected `"
				~ got.type.to!string
				~ "` `"
				~ got.data.to!string
				~ "`; expected `"
				~ expected.map!(x => x.to!string).join("`, `") ~ "`.";
		}

		this.got = got;
		this.expected = expected;

		super(msg(), got.location, file, line);
	}
}

///
struct Document {
	///
	Statement[] statements;
	///
	str file;
}

///
Document parseDocument(str sourceCode, str file = null) @safe pure {
	import std.array : appender;

	auto parser = Parser(sourceCode, file);
	auto statements = appender!(Statement[]);
	foreach (statement; parser) {
		statements ~= statement;
	}
	return Document(statements[], file);
}

///
Statement parseStatement(ref Lexer lexer) @safe pure {
	auto feeder = Feeder(lexer);
	auto result = parseStatement(feeder);
	lexer = feeder._lexer;
	return result;
}

private Statement parseStatement(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	auto expr = parseExpression(feeder);

	if (feeder.empty) {
		throw new UnexpectedEOFException(feeder.front.location);
	}
	if (feeder.front.type != Type.semicolon) {
		throw new UnexpectedTokenException(feeder.front, [Type.semicolon]);
	}

	feeder.popFront();

	return ExpressionStatement(expr);
}

private Expression parseExpression(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	if (feeder.empty) {
		throw new UnexpectedEOFException(feeder.front.location);
	}

	switch (feeder.front.type) {
	case Type.braceSquarOpen:
	case Type.braceCurlyOpen:
	case Type.literalString:
	case Type.literalStringEscaped:
		return parseValueExpression(feeder);

	case Type.identifier:
		return parseExpressionWithIdentifier(feeder);

	default:
		break;
	}

	throw new UnexpectedTokenException(feeder.front, [
		Type.identifier,
		Type.literalString,
		Type.literalStringEscaped,
		Type.braceSquarOpen,
		Type.braceCurlyOpen,
	]);
}

private AppendExpression parseAppendExpression(ref Feeder feeder, SelectorExpression lhs) @safe pure {
	assert(feeder.front.type == Token.Type.opAppend);
	feeder.popFront();

	return parseBinaryExpression!AppendExpression(feeder, lhs);
}

private ArrayLiteralExpression parseArrayLiteralExpression(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	assert(feeder.front.type == Type.braceSquarOpen);
	feeder.popFront();

	ArrayLiteralExpression result = null;

	while (!feeder.empty) {
		if (feeder.front.type == Type.braceSquarClose) {
			feeder.popFront();
			if (result is null) {
				result = new ArrayLiteralExpression();
			}
			return result;
		}

		auto item = parseValueExpression(feeder);

		if (feeder.empty) {
			throw new UnexpectedEOFException(feeder.front.location);
		}

		if (result is null) {
			result = new ArrayLiteralExpression();
		}

		result.items ~= item;

		if (feeder.front.type == Type.braceSquarClose) {
			feeder.popFront();
			return result;
		}

		if (feeder.front.type != Type.comma) {
			throw new UnexpectedTokenException(feeder.front, [
				Type.braceSquarClose,
				Type.comma,
			]);
		}

		feeder.popFront();
	}

	throw new UnexpectedEOFException(feeder.front.location);
}

private AssignmentExpression parseAssignmentExpression(ref Feeder feeder, SelectorExpression lhs) @safe pure {
	assert(feeder.front.type == Token.Type.opAssign);
	feeder.popFront();

	return parseBinaryExpression!AssignmentExpression(feeder, lhs);
}

private T parseBinaryExpression(T : BinaryExpression)(
	ref Feeder feeder,
	SelectorExpression lhs,
) @safe pure {
	auto rhs = parseValueExpression(feeder);
	auto result = new T();
	result.lhs = lhs;
	result.rhs = rhs;
	return result;
}

private CallExpression parseCallExpression(ref Feeder feeder, SelectorExpression functionName) @safe pure {
	alias Type = Token.Type;

	assert(feeder.front.type == Type.braceParenOpen);
	feeder.popFront();

	CallExpression result = null;

	while (!feeder.empty) {
		if (feeder.front.type == Type.braceParenClose) {
			feeder.popFront();
			if (result is null) {
				result = new CallExpression();
				result.functionName = functionName;
			}
			return result;
		}

		auto param = parseValueExpression(feeder);

		if (result is null) {
			result = new CallExpression();
			result.functionName = functionName;
		}

		result.parameters ~= param;

		if (feeder.empty) {
			throw new UnexpectedEOFException(feeder.front.location);
		}

		if (feeder.front.type == Type.braceParenClose) {
			feeder.popFront();
			return result;
		}

		if (feeder.front.type != Type.comma) {
			throw new UnexpectedTokenException(feeder.front, [
				Type.braceParenClose,
				Type.comma,
			]);
		}

		feeder.popFront();
	}

	throw new UnexpectedEOFException(feeder.front.location);
}

private SelectorExpression parseSelectorExpression(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	SelectorExpression result;

	while (!feeder.empty) {
		if (feeder.front.type != Type.identifier) {
			throw new UnexpectedTokenException(feeder.front, [Type.identifier]);
		}

		if (result is null) {
			result = new SelectorExpression();
		}
		result.identifiers ~= feeder.front.data;

		feeder.popFront();
		if (feeder.empty || (feeder.front.type != Type.dot)) {
			return result;
		}

		feeder.popFront();
	}

	throw new UnexpectedEOFException(feeder.front.location);
}

private Expression parseExpressionWithIdentifier(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	auto lhs = parseSelectorExpression(feeder);

	switch (feeder.front.type) {
	case Type.braceParenOpen:
		return parseCallExpression(feeder, lhs);

	case Type.opAppend:
		return parseAppendExpression(feeder, lhs);

	case Type.opAssign:
		return parseAssignmentExpression(feeder, lhs);

	default:
		break;
	}

	throw new UnexpectedTokenException(feeder.front, [
		Type.braceParenOpen,
		Type.opAssign,
		Type.opAppend,
	]);
}

private LiteralExpression parseLiteralExpression(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	if (feeder.empty) {
		throw new UnexpectedEOFException(feeder.front.location);
	}

	switch (feeder.front.type) {
	case Type.braceCurlyOpen:
		return parseObjectLiteralExpression(feeder);

	case Type.braceSquarOpen:
		return parseArrayLiteralExpression(feeder);

	case Type.literalString:
	case Type.literalStringEscaped:
		return parseStringLiteralExpression(feeder);

	default:
		break;
	}

	throw new UnexpectedTokenException(feeder.front, [
		Type.braceCurlyOpen,
		Type.braceSquarOpen,
		Type.literalString,
		Type.literalStringEscaped,
	]);
}

private ObjectLiteralExpression parseObjectLiteralExpression(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	assert(feeder.front.type == Type.braceCurlyOpen);
	feeder.popFront();

	ObjectLiteralExpression result = null;

	while (!feeder.empty) {
		if (feeder.front.type == Type.braceCurlyClose) {
			feeder.popFront();
			if (result is null) {
				result = new ObjectLiteralExpression();
			}
			return result;
		}

		if (
			(feeder.front.type != Type.identifier) &&
			(feeder.front.type != Type.literalString) &&
			(feeder.front.type != Type.literalStringEscaped)
			) {
			throw new UnexpectedTokenException(feeder.front, [Type.identifier]);
		}
		Token key = feeder.front;

		feeder.popFront();
		if (feeder.empty) {
			throw new UnexpectedEOFException(feeder.front.location);
		}

		if (feeder.front.type != Type.colon) {
			throw new UnexpectedTokenException(feeder.front, [Type.colon]);
		}

		feeder.popFront();
		if (feeder.empty) {
			throw new UnexpectedEOFException(feeder.front.location);
		}

		auto value = parseValueExpression(feeder);

		if (feeder.empty) {
			throw new UnexpectedEOFException(feeder.front.location);
		}

		if (result is null) {
			result = new ObjectLiteralExpression();
		}
		else {
			const alreadyExisting = ((key.data in result.properties) !is null);
			if (alreadyExisting) {
				throw new DuplicateObjectPropertyNameException(key.data, key.location);
			}
		}

		auto keyName = (key.type == Type.identifier) ? key.data : parseStringLiteral(key);
		result.properties[keyName] = value;

		if (feeder.front.type == Type.braceCurlyClose) {
			feeder.popFront();
			return result;
		}

		if (feeder.front.type != Type.comma) {
			throw new UnexpectedTokenException(feeder.front, [
				Type.braceCurlyClose,
				Type.comma,
			]);
		}

		feeder.popFront();
	}

	throw new UnexpectedEOFException(feeder.front.location);
}

private string charToEscapeSequence(const char c) @safe pure nothrow @nogc {
	switch (c) {
	case '\\':
		return `\\`;
	case '\'':
		return `\'`;
	case '"':
		return `\"`;
	case '\x00':
		return `\0`;
	case '\x07':
		return `\a`;
	case '\x08':
		return `\b`;
	case '\x0C':
		return `\f`;
	case '\x0A':
		return `\n`;
	case '\x0D':
		return `\r`;
	case '\x09':
		return `\t`;
	case '\x0B':
		return `\v`;
	default:
		break;
	}

	return null;
}

private str parseStringLiteral(Token token) @safe pure {
	import std.conv : text;

	static char escapeSequenceToChar(char seq1, Location loc) {
		switch (seq1) {
		case '\'':
		case '"':
		case '?':
		case '\\':
			return seq1;
		case '0':
			return '\x00';
		case 'a':
			return '\x07';
		case 'b':
			return '\x08';
		case 'f':
			return '\x0C';
		case 'n':
			return '\x0A';
		case 'r':
			return '\x0D';
		case 't':
			return '\x09';
		case 'v':
			return '\x0B';
		default:
			break;
		}

		throw new ParserException("Invalid escape sequence `\\" ~ seq1 ~ "` encountered in string literal.", loc);
	}

	const raw = token.data;

	if (raw.length == 0) {
		throw new ParserException("Bad string literal.", token.location);
	}

	if (raw.length == 1) {
		throw new ParserException("Unterminated string literal.", token.location);
	}

	if (raw[0] != raw[$ - 1]) {
		throw new ParserException("Unsupported string literal.", token.location);
	}

	const trimmed = raw[1 .. ($ - 1)];

	if (token.type == Token.Type.literalStringEscaped) {
		size_t length = trimmed.length;
		bool prevWasBackslash = false;
		foreach (c; trimmed) {
			if (prevWasBackslash) {
				--length;
				prevWasBackslash = false;
				continue;
			}
			prevWasBackslash = (c == '\\');
		}

		auto result = new char[](length);
		auto bufferToFill = result;
		prevWasBackslash = false;
		foreach (char c; trimmed) {
			if (prevWasBackslash) {
				prevWasBackslash = false;
				c = escapeSequenceToChar(c, token.location);
			}
			else {
				prevWasBackslash = (c == '\\');
				if (prevWasBackslash) {
					continue;
				}
			}

			bufferToFill[0] = c;
			bufferToFill = bufferToFill[1 .. $];
		}

		return result;
	}
	else {
		assert(token.type == Token.Type.literalString);
	}

	return trimmed;
}

private StringLiteralExpression parseStringLiteralExpression(ref Feeder feeder) @safe pure {
	assert(
		(feeder.front.type == Token.Type.literalString) ||
			(feeder.front.type == Token.Type.literalStringEscaped)
	);

	auto value = parseStringLiteral(feeder.front);
	feeder.popFront();

	auto result = new StringLiteralExpression();
	result.value = value;
	return result;
}

private ValueExpression parseValueExpression(ref Feeder feeder) @safe pure {
	alias Data = ValueExpression.Data;
	alias Type = Token.Type;

	static Data parseData(ref Feeder feeder) {
		if (feeder.empty) {
			throw new UnexpectedEOFException(feeder.front.location);
		}

		switch (feeder.front.type) {
		case Type.identifier:
			return parseCallOrVariableExpression(feeder);

		case Type.braceCurlyOpen:
		case Type.braceSquarOpen:
		case Type.literalString:
		case Type.literalStringEscaped:
			return Data(parseLiteralExpression(feeder));

		default:
			break;
		}

		throw new UnexpectedTokenException(feeder.front, [
			Type.braceCurlyOpen,
			Type.braceSquarOpen,
			Type.identifier,
			Type.literalString,
			Type.literalStringEscaped,
		]);
	}

	auto data = parseData(feeder);

	auto result = new ValueExpression();
	result.data = data;
	return result;
}

private ValueExpression.Data parseCallOrVariableExpression(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	if (feeder.empty) {
		throw new UnexpectedEOFException(feeder.front.location);
	}

	auto selector = parseSelectorExpression(feeder);

	if (feeder.empty || (feeder.front.type != Type.braceParenOpen)) {
		auto variable = new VariableExpression();
		variable.selector = selector;
		return ValueExpression.Data(variable);
	}

	auto call = parseCallExpression(feeder, selector);

	return ValueExpression.Data(call);
}

private VariableExpression parseVariableExpression(ref Feeder feeder) @safe pure {
	alias Type = Token.Type;

	if (feeder.empty) {
		throw new UnexpectedEOFException(feeder.front.location);
	}

	auto selector = parseSelectorExpression(feeder);

	auto result = new VariableExpression();
	result.selector = selector;
	return result;
}

// Statements

///
alias Statement = ExpressionStatement;

///
struct ExpressionStatement {
	public {
		///
		Expression expression;
	}

@safe pure:

	///
	string toString() const {
		if (expression is null) {
			return "\n";
		}

		auto printer = CodePrinter("\t", 0);
		this.toString(printer);
		return printer.toString();
	}

	///
	void toString(ref CodePrinter printer) const {
		if (expression is null) {
			printer.printLine();
			return;
		}
		expression.toString(printer);
		printer.print(";\n");
	}
}

// Expressions

///
abstract class Expression {
@safe pure:

	///
	public this() {
	}

	///
	public final override string toString() const {
		auto printer = CodePrinter("\t", 0);
		this.toString(printer);
		return printer.toString();
	}

	///
	public abstract void toString(ref CodePrinter printer) const;
}

final class AppendExpression : BinaryExpression {
@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		lhs.toString(printer);
		printer.print(" ~= ");
		rhs.toString(printer);
	}
}

///
final class ArrayLiteralExpression : LiteralExpression {
	public {
		///
		ValueExpression[] items;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		printer.startBlock("[");
		foreach (item; items) {
			printer.printIdentation();
			item.toString(printer);
			printer.print(",\n");
		}
		printer.endBlock("]");
	}
}

///
final class AssignmentExpression : BinaryExpression {
@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		lhs.toString(printer);
		printer.print(" = ");
		rhs.toString(printer);
	}
}

///
abstract class BinaryExpression : Expression {
	public {
		///
		SelectorExpression lhs;
		///
		ValueExpression rhs;
	}

@safe pure:

	public this() {
		super();
	}
}

///
final class BooleanLiteralExpression : LiteralExpression {
	public {
		///
		bool value;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		const printable = (value) ? "true" : "false";
		printer.print(printable);
	}
}

///
final class CallExpression : Expression {
	public {
		///
		SelectorExpression functionName;
		///
		ValueExpression[] parameters;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		functionName.toString(printer);
		printer.print("(");
		foreach (idx, parameter; parameters) {
			if (idx > 0) {
				printer.print(", ");
			}
			parameter.toString(printer);
		}
		printer.print(")");
	}
}

///
abstract class LiteralExpression : Expression {
@safe pure:

	public this() {
		super();
	}
}

///
final class ObjectLiteralExpression : LiteralExpression {
	public {
		///
		ValueExpression[string] properties;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		printer.startBlock("{");
		if (properties.length > 0) {
			printer.print("\n");
		}
		foreach (key, value; properties) {
			printer.printIdentation();
			if (key.length != scanIdentifier(key)) {
				StringLiteralExpression.printEscaped(printer, key);
				printer.print(": ");
			}
			else {
				printer.print(key, ": ");
			}
			value.toString(printer);
			printer.print(",\n");
		}
		printer.endBlock("}");
	}
}

///
final class SelectorExpression : Expression {
	public {
		///
		str[] identifiers;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		foreach (idx, identifier; identifiers) {
			if (idx > 0) {
				printer.print(".");
			}
			printer.print(identifier);
		}
	}
}

///
final class StringLiteralExpression : LiteralExpression {
	public {
		///
		str value;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		return this.printEscaped(printer, value);
	}

	private static void printEscaped(ref CodePrinter printer, str value) {
		printer.print("\"");
		size_t from = 0;
		foreach (idx, c; value) {
			const escapeSeq = charToEscapeSequence(c);
			if (escapeSeq !is null) {
				printer.print(value[from .. idx]);
				printer.print(escapeSeq);
				from = idx + 1;
			}
		}
		printer.print(value[from .. $]);
		printer.print("\"");
	}
}

///
final class ValueExpression : Expression {

	///
	public alias Data = TaggedUnion!(
		CallExpression,
		LiteralExpression,
		VariableExpression,
	);

	public {
		///
		Data data;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		if (data.has!CallExpression) {
			return data.get!CallExpression.toString(printer);
		}
		if (data.has!LiteralExpression) {
			return data.get!LiteralExpression.toString(printer);
		}
		if (data.has!VariableExpression) {
			return data.get!VariableExpression.toString(printer);
		}

		assert(false, "ICE: Missing handler for a union type of `ValueExpression`.");
	}
}

///
final class VariableExpression : Expression {
	public {
		///
		SelectorExpression selector;
	}

@safe pure:

	public this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		selector.toString(printer);
	}
}
