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
		literalString = '"',

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
		_loc = Location(0, file, input);
		this.loadFrontInitial();
	}

	public {
		///
		bool empty() const {
			return (_input is null);
		}

		///
		inout(Token) front() inout {
			return _front;
		}

		///
		void popFront() {
			if (_front.type == Type.eof) {
				_input = null;
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
			ptrdiff_t scanForClosingDoubleQuote(str input) {
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
				const idxEnd = scanForClosingDoubleQuote(_input[1 .. $]);
				const length = (idxEnd < 0) ? _input.length : (1 + idxEnd + 1);
				return this.makeToken(Type.literalString, length);
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
	}

	public {
		///
		bool empty() const {
			return _lexer.empty;
		}

		///
		inout(Token) front() inout {
			return _lexer.front;
		}

		///
		void popFront() {
			while (!_lexer.empty) {
				if (!this.shallSkip()) {
					return;
				}
			}
		}
	}

	private {
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

		inout(Statement) front() inout nothrow @nogc {
			return _front;
		}

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
	// TODO: implement
	assert(false, "Not implemented.");
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
		return expression.toString();
	}

	///
	void toString(ref CodePrinter printer) const {
		if (expression is null) {
			printer.printLine();
			return;
		}
		return expression.toString(printer);
	}
}

// Expressions

///
abstract class Expression {
@safe pure:

	private this() {
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

///
final class ArrayLiteralExpression : Expression {
	public {
		///
		ValueExpression items;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
final class AssignmentExpression : Expression {
	public {
		///
		SelectorExpression lhs;
		///
		ValueExpression rhs;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
final class BooleanLiteralExpression : LiteralExpression {
	public {
		///
		bool value;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
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

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
abstract class LiteralExpression : Expression {
@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
final class ObjectLiteralExpression : LiteralExpression {
	public {
		///
		ValueExpression[string] members;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
final class SelectorExpression : Expression {
	public {
		///
		str[] identifiers;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
final class StringLiteralExpression : LiteralExpression {
	public {
		///
		str value;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
final class ValueExpression : Expression {

	///
	public alias Data = TaggedUnion!(
		LiteralExpression,
		VariableExpression,
	);

	public {
		///
		Data data;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}

///
final class VariableExpression : Expression {
	public {
		///
		SelectorExpression selector;
	}

@safe pure:

	private this() {
		super();
	}

	///
	public override void toString(ref CodePrinter printer) const {
		// TODO: implement
		assert(false, "Not implemented.");
	}
}
