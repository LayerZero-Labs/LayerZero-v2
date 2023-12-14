/* eslint-disable */
//prettier-ignore
module.exports = {
name: "@yarnpkg/plugin-forge",
factory: function (require) {
var plugin = (() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __require = /* @__PURE__ */ ((x) => typeof require !== "undefined" ? require : typeof Proxy !== "undefined" ? new Proxy(x, {
    get: (a, b) => (typeof require !== "undefined" ? require : a)[b]
  }) : x)(function(x) {
    if (typeof require !== "undefined")
      return require.apply(this, arguments);
    throw new Error('Dynamic require of "' + x + '" is not supported');
  });
  var __commonJS = (cb, mod) => function __require2() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/parser.js
  var require_parser = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/parser.js"(exports2, module2) {
      "use strict";
      var ParserEND = 1114112;
      var ParserError = class extends Error {
        constructor(msg, filename, linenumber) {
          super("[ParserError] " + msg, filename, linenumber);
          this.name = "ParserError";
          this.code = "ParserError";
          if (Error.captureStackTrace)
            Error.captureStackTrace(this, ParserError);
        }
      };
      var State = class {
        constructor(parser) {
          this.parser = parser;
          this.buf = "";
          this.returned = null;
          this.result = null;
          this.resultTable = null;
          this.resultArr = null;
        }
      };
      var Parser = class {
        constructor() {
          this.pos = 0;
          this.col = 0;
          this.line = 0;
          this.obj = {};
          this.ctx = this.obj;
          this.stack = [];
          this._buf = "";
          this.char = null;
          this.ii = 0;
          this.state = new State(this.parseStart);
        }
        parse(str) {
          if (str.length === 0 || str.length == null)
            return;
          this._buf = String(str);
          this.ii = -1;
          this.char = -1;
          let getNext;
          while (getNext === false || this.nextChar()) {
            getNext = this.runOne();
          }
          this._buf = null;
        }
        nextChar() {
          if (this.char === 10) {
            ++this.line;
            this.col = -1;
          }
          ++this.ii;
          this.char = this._buf.codePointAt(this.ii);
          ++this.pos;
          ++this.col;
          return this.haveBuffer();
        }
        haveBuffer() {
          return this.ii < this._buf.length;
        }
        runOne() {
          return this.state.parser.call(this, this.state.returned);
        }
        finish() {
          this.char = ParserEND;
          let last;
          do {
            last = this.state.parser;
            this.runOne();
          } while (this.state.parser !== last);
          this.ctx = null;
          this.state = null;
          this._buf = null;
          return this.obj;
        }
        next(fn) {
          if (typeof fn !== "function")
            throw new ParserError("Tried to set state to non-existent state: " + JSON.stringify(fn));
          this.state.parser = fn;
        }
        goto(fn) {
          this.next(fn);
          return this.runOne();
        }
        call(fn, returnWith) {
          if (returnWith)
            this.next(returnWith);
          this.stack.push(this.state);
          this.state = new State(fn);
        }
        callNow(fn, returnWith) {
          this.call(fn, returnWith);
          return this.runOne();
        }
        return(value) {
          if (this.stack.length === 0)
            throw this.error(new ParserError("Stack underflow"));
          if (value === void 0)
            value = this.state.buf;
          this.state = this.stack.pop();
          this.state.returned = value;
        }
        returnNow(value) {
          this.return(value);
          return this.runOne();
        }
        consume() {
          if (this.char === ParserEND)
            throw this.error(new ParserError("Unexpected end-of-buffer"));
          this.state.buf += this._buf[this.ii];
        }
        error(err) {
          err.line = this.line;
          err.col = this.col;
          err.pos = this.pos;
          return err;
        }
        parseStart() {
          throw new ParserError("Must declare a parseStart method");
        }
      };
      Parser.END = ParserEND;
      Parser.Error = ParserError;
      module2.exports = Parser;
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-datetime.js
  var require_create_datetime = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-datetime.js"(exports2, module2) {
      "use strict";
      module2.exports = (value) => {
        const date = new Date(value);
        if (isNaN(date)) {
          throw new TypeError("Invalid Datetime");
        } else {
          return date;
        }
      };
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/format-num.js
  var require_format_num = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/format-num.js"(exports2, module2) {
      "use strict";
      module2.exports = (d, num) => {
        num = String(num);
        while (num.length < d)
          num = "0" + num;
        return num;
      };
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-datetime-float.js
  var require_create_datetime_float = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-datetime-float.js"(exports2, module2) {
      "use strict";
      var f = require_format_num();
      var FloatingDateTime = class extends Date {
        constructor(value) {
          super(value + "Z");
          this.isFloating = true;
        }
        toISOString() {
          const date = `${this.getUTCFullYear()}-${f(2, this.getUTCMonth() + 1)}-${f(2, this.getUTCDate())}`;
          const time = `${f(2, this.getUTCHours())}:${f(2, this.getUTCMinutes())}:${f(2, this.getUTCSeconds())}.${f(3, this.getUTCMilliseconds())}`;
          return `${date}T${time}`;
        }
      };
      module2.exports = (value) => {
        const date = new FloatingDateTime(value);
        if (isNaN(date)) {
          throw new TypeError("Invalid Datetime");
        } else {
          return date;
        }
      };
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-date.js
  var require_create_date = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-date.js"(exports2, module2) {
      "use strict";
      var f = require_format_num();
      var DateTime = global.Date;
      var Date2 = class extends DateTime {
        constructor(value) {
          super(value);
          this.isDate = true;
        }
        toISOString() {
          return `${this.getUTCFullYear()}-${f(2, this.getUTCMonth() + 1)}-${f(2, this.getUTCDate())}`;
        }
      };
      module2.exports = (value) => {
        const date = new Date2(value);
        if (isNaN(date)) {
          throw new TypeError("Invalid Datetime");
        } else {
          return date;
        }
      };
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-time.js
  var require_create_time = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/create-time.js"(exports2, module2) {
      "use strict";
      var f = require_format_num();
      var Time = class extends Date {
        constructor(value) {
          super(`0000-01-01T${value}Z`);
          this.isTime = true;
        }
        toISOString() {
          return `${f(2, this.getUTCHours())}:${f(2, this.getUTCMinutes())}:${f(2, this.getUTCSeconds())}.${f(3, this.getUTCMilliseconds())}`;
        }
      };
      module2.exports = (value) => {
        const date = new Time(value);
        if (isNaN(date)) {
          throw new TypeError("Invalid Datetime");
        } else {
          return date;
        }
      };
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/toml-parser.js
  var require_toml_parser = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/lib/toml-parser.js"(exports, module) {
      "use strict";
      module.exports = makeParserClass(require_parser());
      module.exports.makeParserClass = makeParserClass;
      var TomlError = class extends Error {
        constructor(msg) {
          super(msg);
          this.name = "TomlError";
          if (Error.captureStackTrace)
            Error.captureStackTrace(this, TomlError);
          this.fromTOML = true;
          this.wrapped = null;
        }
      };
      TomlError.wrap = (err) => {
        const terr = new TomlError(err.message);
        terr.code = err.code;
        terr.wrapped = err;
        return terr;
      };
      module.exports.TomlError = TomlError;
      var createDateTime = require_create_datetime();
      var createDateTimeFloat = require_create_datetime_float();
      var createDate = require_create_date();
      var createTime = require_create_time();
      var CTRL_I = 9;
      var CTRL_J = 10;
      var CTRL_M = 13;
      var CTRL_CHAR_BOUNDARY = 31;
      var CHAR_SP = 32;
      var CHAR_QUOT = 34;
      var CHAR_NUM = 35;
      var CHAR_APOS = 39;
      var CHAR_PLUS = 43;
      var CHAR_COMMA = 44;
      var CHAR_HYPHEN = 45;
      var CHAR_PERIOD = 46;
      var CHAR_0 = 48;
      var CHAR_1 = 49;
      var CHAR_7 = 55;
      var CHAR_9 = 57;
      var CHAR_COLON = 58;
      var CHAR_EQUALS = 61;
      var CHAR_A = 65;
      var CHAR_E = 69;
      var CHAR_F = 70;
      var CHAR_T = 84;
      var CHAR_U = 85;
      var CHAR_Z = 90;
      var CHAR_LOWBAR = 95;
      var CHAR_a = 97;
      var CHAR_b = 98;
      var CHAR_e = 101;
      var CHAR_f = 102;
      var CHAR_i = 105;
      var CHAR_l = 108;
      var CHAR_n = 110;
      var CHAR_o = 111;
      var CHAR_r = 114;
      var CHAR_s = 115;
      var CHAR_t = 116;
      var CHAR_u = 117;
      var CHAR_x = 120;
      var CHAR_z = 122;
      var CHAR_LCUB = 123;
      var CHAR_RCUB = 125;
      var CHAR_LSQB = 91;
      var CHAR_BSOL = 92;
      var CHAR_RSQB = 93;
      var CHAR_DEL = 127;
      var SURROGATE_FIRST = 55296;
      var SURROGATE_LAST = 57343;
      var escapes = {
        [CHAR_b]: "\b",
        [CHAR_t]: "	",
        [CHAR_n]: "\n",
        [CHAR_f]: "\f",
        [CHAR_r]: "\r",
        [CHAR_QUOT]: '"',
        [CHAR_BSOL]: "\\"
      };
      function isDigit(cp) {
        return cp >= CHAR_0 && cp <= CHAR_9;
      }
      function isHexit(cp) {
        return cp >= CHAR_A && cp <= CHAR_F || cp >= CHAR_a && cp <= CHAR_f || cp >= CHAR_0 && cp <= CHAR_9;
      }
      function isBit(cp) {
        return cp === CHAR_1 || cp === CHAR_0;
      }
      function isOctit(cp) {
        return cp >= CHAR_0 && cp <= CHAR_7;
      }
      function isAlphaNumQuoteHyphen(cp) {
        return cp >= CHAR_A && cp <= CHAR_Z || cp >= CHAR_a && cp <= CHAR_z || cp >= CHAR_0 && cp <= CHAR_9 || cp === CHAR_APOS || cp === CHAR_QUOT || cp === CHAR_LOWBAR || cp === CHAR_HYPHEN;
      }
      function isAlphaNumHyphen(cp) {
        return cp >= CHAR_A && cp <= CHAR_Z || cp >= CHAR_a && cp <= CHAR_z || cp >= CHAR_0 && cp <= CHAR_9 || cp === CHAR_LOWBAR || cp === CHAR_HYPHEN;
      }
      var _type = Symbol("type");
      var _declared = Symbol("declared");
      var hasOwnProperty = Object.prototype.hasOwnProperty;
      var defineProperty = Object.defineProperty;
      var descriptor = { configurable: true, enumerable: true, writable: true, value: void 0 };
      function hasKey(obj, key) {
        if (hasOwnProperty.call(obj, key))
          return true;
        if (key === "__proto__")
          defineProperty(obj, "__proto__", descriptor);
        return false;
      }
      var INLINE_TABLE = Symbol("inline-table");
      function InlineTable() {
        return Object.defineProperties({}, {
          [_type]: { value: INLINE_TABLE }
        });
      }
      function isInlineTable(obj) {
        if (obj === null || typeof obj !== "object")
          return false;
        return obj[_type] === INLINE_TABLE;
      }
      var TABLE = Symbol("table");
      function Table() {
        return Object.defineProperties({}, {
          [_type]: { value: TABLE },
          [_declared]: { value: false, writable: true }
        });
      }
      function isTable(obj) {
        if (obj === null || typeof obj !== "object")
          return false;
        return obj[_type] === TABLE;
      }
      var _contentType = Symbol("content-type");
      var INLINE_LIST = Symbol("inline-list");
      function InlineList(type) {
        return Object.defineProperties([], {
          [_type]: { value: INLINE_LIST },
          [_contentType]: { value: type }
        });
      }
      function isInlineList(obj) {
        if (obj === null || typeof obj !== "object")
          return false;
        return obj[_type] === INLINE_LIST;
      }
      var LIST = Symbol("list");
      function List() {
        return Object.defineProperties([], {
          [_type]: { value: LIST }
        });
      }
      function isList(obj) {
        if (obj === null || typeof obj !== "object")
          return false;
        return obj[_type] === LIST;
      }
      var _custom;
      try {
        const utilInspect = eval("require('util').inspect");
        _custom = utilInspect.custom;
      } catch (_) {
      }
      var _inspect = _custom || "inspect";
      var BoxedBigInt = class {
        constructor(value) {
          try {
            this.value = global.BigInt.asIntN(64, value);
          } catch (_) {
            this.value = null;
          }
          Object.defineProperty(this, _type, { value: INTEGER });
        }
        isNaN() {
          return this.value === null;
        }
        toString() {
          return String(this.value);
        }
        [_inspect]() {
          return `[BigInt: ${this.toString()}]}`;
        }
        valueOf() {
          return this.value;
        }
      };
      var INTEGER = Symbol("integer");
      function Integer(value) {
        let num = Number(value);
        if (Object.is(num, -0))
          num = 0;
        if (global.BigInt && !Number.isSafeInteger(num)) {
          return new BoxedBigInt(value);
        } else {
          return Object.defineProperties(new Number(num), {
            isNaN: { value: function() {
              return isNaN(this);
            } },
            [_type]: { value: INTEGER },
            [_inspect]: { value: () => `[Integer: ${value}]` }
          });
        }
      }
      function isInteger(obj) {
        if (obj === null || typeof obj !== "object")
          return false;
        return obj[_type] === INTEGER;
      }
      var FLOAT = Symbol("float");
      function Float(value) {
        return Object.defineProperties(new Number(value), {
          [_type]: { value: FLOAT },
          [_inspect]: { value: () => `[Float: ${value}]` }
        });
      }
      function isFloat(obj) {
        if (obj === null || typeof obj !== "object")
          return false;
        return obj[_type] === FLOAT;
      }
      function tomlType(value) {
        const type = typeof value;
        if (type === "object") {
          if (value === null)
            return "null";
          if (value instanceof Date)
            return "datetime";
          if (_type in value) {
            switch (value[_type]) {
              case INLINE_TABLE:
                return "inline-table";
              case INLINE_LIST:
                return "inline-list";
              case TABLE:
                return "table";
              case LIST:
                return "list";
              case FLOAT:
                return "float";
              case INTEGER:
                return "integer";
            }
          }
        }
        return type;
      }
      function makeParserClass(Parser) {
        class TOMLParser extends Parser {
          constructor() {
            super();
            this.ctx = this.obj = Table();
          }
          atEndOfWord() {
            return this.char === CHAR_NUM || this.char === CTRL_I || this.char === CHAR_SP || this.atEndOfLine();
          }
          atEndOfLine() {
            return this.char === Parser.END || this.char === CTRL_J || this.char === CTRL_M;
          }
          parseStart() {
            if (this.char === Parser.END) {
              return null;
            } else if (this.char === CHAR_LSQB) {
              return this.call(this.parseTableOrList);
            } else if (this.char === CHAR_NUM) {
              return this.call(this.parseComment);
            } else if (this.char === CTRL_J || this.char === CHAR_SP || this.char === CTRL_I || this.char === CTRL_M) {
              return null;
            } else if (isAlphaNumQuoteHyphen(this.char)) {
              return this.callNow(this.parseAssignStatement);
            } else {
              throw this.error(new TomlError(`Unknown character "${this.char}"`));
            }
          }
          parseWhitespaceToEOL() {
            if (this.char === CHAR_SP || this.char === CTRL_I || this.char === CTRL_M) {
              return null;
            } else if (this.char === CHAR_NUM) {
              return this.goto(this.parseComment);
            } else if (this.char === Parser.END || this.char === CTRL_J) {
              return this.return();
            } else {
              throw this.error(new TomlError("Unexpected character, expected only whitespace or comments till end of line"));
            }
          }
          parseAssignStatement() {
            return this.callNow(this.parseAssign, this.recordAssignStatement);
          }
          recordAssignStatement(kv) {
            let target = this.ctx;
            let finalKey = kv.key.pop();
            for (let kw of kv.key) {
              if (hasKey(target, kw) && (!isTable(target[kw]) || target[kw][_declared])) {
                throw this.error(new TomlError("Can't redefine existing key"));
              }
              target = target[kw] = target[kw] || Table();
            }
            if (hasKey(target, finalKey)) {
              throw this.error(new TomlError("Can't redefine existing key"));
            }
            if (isInteger(kv.value) || isFloat(kv.value)) {
              target[finalKey] = kv.value.valueOf();
            } else {
              target[finalKey] = kv.value;
            }
            return this.goto(this.parseWhitespaceToEOL);
          }
          parseAssign() {
            return this.callNow(this.parseKeyword, this.recordAssignKeyword);
          }
          recordAssignKeyword(key) {
            if (this.state.resultTable) {
              this.state.resultTable.push(key);
            } else {
              this.state.resultTable = [key];
            }
            return this.goto(this.parseAssignKeywordPreDot);
          }
          parseAssignKeywordPreDot() {
            if (this.char === CHAR_PERIOD) {
              return this.next(this.parseAssignKeywordPostDot);
            } else if (this.char !== CHAR_SP && this.char !== CTRL_I) {
              return this.goto(this.parseAssignEqual);
            }
          }
          parseAssignKeywordPostDot() {
            if (this.char !== CHAR_SP && this.char !== CTRL_I) {
              return this.callNow(this.parseKeyword, this.recordAssignKeyword);
            }
          }
          parseAssignEqual() {
            if (this.char === CHAR_EQUALS) {
              return this.next(this.parseAssignPreValue);
            } else {
              throw this.error(new TomlError('Invalid character, expected "="'));
            }
          }
          parseAssignPreValue() {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else {
              return this.callNow(this.parseValue, this.recordAssignValue);
            }
          }
          recordAssignValue(value) {
            return this.returnNow({ key: this.state.resultTable, value });
          }
          parseComment() {
            do {
              if (this.char === Parser.END || this.char === CTRL_J) {
                return this.return();
              }
            } while (this.nextChar());
          }
          parseTableOrList() {
            if (this.char === CHAR_LSQB) {
              this.next(this.parseList);
            } else {
              return this.goto(this.parseTable);
            }
          }
          parseTable() {
            this.ctx = this.obj;
            return this.goto(this.parseTableNext);
          }
          parseTableNext() {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else {
              return this.callNow(this.parseKeyword, this.parseTableMore);
            }
          }
          parseTableMore(keyword) {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else if (this.char === CHAR_RSQB) {
              if (hasKey(this.ctx, keyword) && (!isTable(this.ctx[keyword]) || this.ctx[keyword][_declared])) {
                throw this.error(new TomlError("Can't redefine existing key"));
              } else {
                this.ctx = this.ctx[keyword] = this.ctx[keyword] || Table();
                this.ctx[_declared] = true;
              }
              return this.next(this.parseWhitespaceToEOL);
            } else if (this.char === CHAR_PERIOD) {
              if (!hasKey(this.ctx, keyword)) {
                this.ctx = this.ctx[keyword] = Table();
              } else if (isTable(this.ctx[keyword])) {
                this.ctx = this.ctx[keyword];
              } else if (isList(this.ctx[keyword])) {
                this.ctx = this.ctx[keyword][this.ctx[keyword].length - 1];
              } else {
                throw this.error(new TomlError("Can't redefine existing key"));
              }
              return this.next(this.parseTableNext);
            } else {
              throw this.error(new TomlError("Unexpected character, expected whitespace, . or ]"));
            }
          }
          parseList() {
            this.ctx = this.obj;
            return this.goto(this.parseListNext);
          }
          parseListNext() {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else {
              return this.callNow(this.parseKeyword, this.parseListMore);
            }
          }
          parseListMore(keyword) {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else if (this.char === CHAR_RSQB) {
              if (!hasKey(this.ctx, keyword)) {
                this.ctx[keyword] = List();
              }
              if (isInlineList(this.ctx[keyword])) {
                throw this.error(new TomlError("Can't extend an inline array"));
              } else if (isList(this.ctx[keyword])) {
                const next = Table();
                this.ctx[keyword].push(next);
                this.ctx = next;
              } else {
                throw this.error(new TomlError("Can't redefine an existing key"));
              }
              return this.next(this.parseListEnd);
            } else if (this.char === CHAR_PERIOD) {
              if (!hasKey(this.ctx, keyword)) {
                this.ctx = this.ctx[keyword] = Table();
              } else if (isInlineList(this.ctx[keyword])) {
                throw this.error(new TomlError("Can't extend an inline array"));
              } else if (isInlineTable(this.ctx[keyword])) {
                throw this.error(new TomlError("Can't extend an inline table"));
              } else if (isList(this.ctx[keyword])) {
                this.ctx = this.ctx[keyword][this.ctx[keyword].length - 1];
              } else if (isTable(this.ctx[keyword])) {
                this.ctx = this.ctx[keyword];
              } else {
                throw this.error(new TomlError("Can't redefine an existing key"));
              }
              return this.next(this.parseListNext);
            } else {
              throw this.error(new TomlError("Unexpected character, expected whitespace, . or ]"));
            }
          }
          parseListEnd(keyword) {
            if (this.char === CHAR_RSQB) {
              return this.next(this.parseWhitespaceToEOL);
            } else {
              throw this.error(new TomlError("Unexpected character, expected whitespace, . or ]"));
            }
          }
          parseValue() {
            if (this.char === Parser.END) {
              throw this.error(new TomlError("Key without value"));
            } else if (this.char === CHAR_QUOT) {
              return this.next(this.parseDoubleString);
            }
            if (this.char === CHAR_APOS) {
              return this.next(this.parseSingleString);
            } else if (this.char === CHAR_HYPHEN || this.char === CHAR_PLUS) {
              return this.goto(this.parseNumberSign);
            } else if (this.char === CHAR_i) {
              return this.next(this.parseInf);
            } else if (this.char === CHAR_n) {
              return this.next(this.parseNan);
            } else if (isDigit(this.char)) {
              return this.goto(this.parseNumberOrDateTime);
            } else if (this.char === CHAR_t || this.char === CHAR_f) {
              return this.goto(this.parseBoolean);
            } else if (this.char === CHAR_LSQB) {
              return this.call(this.parseInlineList, this.recordValue);
            } else if (this.char === CHAR_LCUB) {
              return this.call(this.parseInlineTable, this.recordValue);
            } else {
              throw this.error(new TomlError("Unexpected character, expecting string, number, datetime, boolean, inline array or inline table"));
            }
          }
          recordValue(value) {
            return this.returnNow(value);
          }
          parseInf() {
            if (this.char === CHAR_n) {
              return this.next(this.parseInf2);
            } else {
              throw this.error(new TomlError('Unexpected character, expected "inf", "+inf" or "-inf"'));
            }
          }
          parseInf2() {
            if (this.char === CHAR_f) {
              if (this.state.buf === "-") {
                return this.return(-Infinity);
              } else {
                return this.return(Infinity);
              }
            } else {
              throw this.error(new TomlError('Unexpected character, expected "inf", "+inf" or "-inf"'));
            }
          }
          parseNan() {
            if (this.char === CHAR_a) {
              return this.next(this.parseNan2);
            } else {
              throw this.error(new TomlError('Unexpected character, expected "nan"'));
            }
          }
          parseNan2() {
            if (this.char === CHAR_n) {
              return this.return(NaN);
            } else {
              throw this.error(new TomlError('Unexpected character, expected "nan"'));
            }
          }
          parseKeyword() {
            if (this.char === CHAR_QUOT) {
              return this.next(this.parseBasicString);
            } else if (this.char === CHAR_APOS) {
              return this.next(this.parseLiteralString);
            } else {
              return this.goto(this.parseBareKey);
            }
          }
          parseBareKey() {
            do {
              if (this.char === Parser.END) {
                throw this.error(new TomlError("Key ended without value"));
              } else if (isAlphaNumHyphen(this.char)) {
                this.consume();
              } else if (this.state.buf.length === 0) {
                throw this.error(new TomlError("Empty bare keys are not allowed"));
              } else {
                return this.returnNow();
              }
            } while (this.nextChar());
          }
          parseSingleString() {
            if (this.char === CHAR_APOS) {
              return this.next(this.parseLiteralMultiStringMaybe);
            } else {
              return this.goto(this.parseLiteralString);
            }
          }
          parseLiteralString() {
            do {
              if (this.char === CHAR_APOS) {
                return this.return();
              } else if (this.atEndOfLine()) {
                throw this.error(new TomlError("Unterminated string"));
              } else if (this.char === CHAR_DEL || this.char <= CTRL_CHAR_BOUNDARY && this.char !== CTRL_I) {
                throw this.errorControlCharInString();
              } else {
                this.consume();
              }
            } while (this.nextChar());
          }
          parseLiteralMultiStringMaybe() {
            if (this.char === CHAR_APOS) {
              return this.next(this.parseLiteralMultiString);
            } else {
              return this.returnNow();
            }
          }
          parseLiteralMultiString() {
            if (this.char === CTRL_M) {
              return null;
            } else if (this.char === CTRL_J) {
              return this.next(this.parseLiteralMultiStringContent);
            } else {
              return this.goto(this.parseLiteralMultiStringContent);
            }
          }
          parseLiteralMultiStringContent() {
            do {
              if (this.char === CHAR_APOS) {
                return this.next(this.parseLiteralMultiEnd);
              } else if (this.char === Parser.END) {
                throw this.error(new TomlError("Unterminated multi-line string"));
              } else if (this.char === CHAR_DEL || this.char <= CTRL_CHAR_BOUNDARY && this.char !== CTRL_I && this.char !== CTRL_J && this.char !== CTRL_M) {
                throw this.errorControlCharInString();
              } else {
                this.consume();
              }
            } while (this.nextChar());
          }
          parseLiteralMultiEnd() {
            if (this.char === CHAR_APOS) {
              return this.next(this.parseLiteralMultiEnd2);
            } else {
              this.state.buf += "'";
              return this.goto(this.parseLiteralMultiStringContent);
            }
          }
          parseLiteralMultiEnd2() {
            if (this.char === CHAR_APOS) {
              return this.return();
            } else {
              this.state.buf += "''";
              return this.goto(this.parseLiteralMultiStringContent);
            }
          }
          parseDoubleString() {
            if (this.char === CHAR_QUOT) {
              return this.next(this.parseMultiStringMaybe);
            } else {
              return this.goto(this.parseBasicString);
            }
          }
          parseBasicString() {
            do {
              if (this.char === CHAR_BSOL) {
                return this.call(this.parseEscape, this.recordEscapeReplacement);
              } else if (this.char === CHAR_QUOT) {
                return this.return();
              } else if (this.atEndOfLine()) {
                throw this.error(new TomlError("Unterminated string"));
              } else if (this.char === CHAR_DEL || this.char <= CTRL_CHAR_BOUNDARY && this.char !== CTRL_I) {
                throw this.errorControlCharInString();
              } else {
                this.consume();
              }
            } while (this.nextChar());
          }
          recordEscapeReplacement(replacement) {
            this.state.buf += replacement;
            return this.goto(this.parseBasicString);
          }
          parseMultiStringMaybe() {
            if (this.char === CHAR_QUOT) {
              return this.next(this.parseMultiString);
            } else {
              return this.returnNow();
            }
          }
          parseMultiString() {
            if (this.char === CTRL_M) {
              return null;
            } else if (this.char === CTRL_J) {
              return this.next(this.parseMultiStringContent);
            } else {
              return this.goto(this.parseMultiStringContent);
            }
          }
          parseMultiStringContent() {
            do {
              if (this.char === CHAR_BSOL) {
                return this.call(this.parseMultiEscape, this.recordMultiEscapeReplacement);
              } else if (this.char === CHAR_QUOT) {
                return this.next(this.parseMultiEnd);
              } else if (this.char === Parser.END) {
                throw this.error(new TomlError("Unterminated multi-line string"));
              } else if (this.char === CHAR_DEL || this.char <= CTRL_CHAR_BOUNDARY && this.char !== CTRL_I && this.char !== CTRL_J && this.char !== CTRL_M) {
                throw this.errorControlCharInString();
              } else {
                this.consume();
              }
            } while (this.nextChar());
          }
          errorControlCharInString() {
            let displayCode = "\\u00";
            if (this.char < 16) {
              displayCode += "0";
            }
            displayCode += this.char.toString(16);
            return this.error(new TomlError(`Control characters (codes < 0x1f and 0x7f) are not allowed in strings, use ${displayCode} instead`));
          }
          recordMultiEscapeReplacement(replacement) {
            this.state.buf += replacement;
            return this.goto(this.parseMultiStringContent);
          }
          parseMultiEnd() {
            if (this.char === CHAR_QUOT) {
              return this.next(this.parseMultiEnd2);
            } else {
              this.state.buf += '"';
              return this.goto(this.parseMultiStringContent);
            }
          }
          parseMultiEnd2() {
            if (this.char === CHAR_QUOT) {
              return this.return();
            } else {
              this.state.buf += '""';
              return this.goto(this.parseMultiStringContent);
            }
          }
          parseMultiEscape() {
            if (this.char === CTRL_M || this.char === CTRL_J) {
              return this.next(this.parseMultiTrim);
            } else if (this.char === CHAR_SP || this.char === CTRL_I) {
              return this.next(this.parsePreMultiTrim);
            } else {
              return this.goto(this.parseEscape);
            }
          }
          parsePreMultiTrim() {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else if (this.char === CTRL_M || this.char === CTRL_J) {
              return this.next(this.parseMultiTrim);
            } else {
              throw this.error(new TomlError("Can't escape whitespace"));
            }
          }
          parseMultiTrim() {
            if (this.char === CTRL_J || this.char === CHAR_SP || this.char === CTRL_I || this.char === CTRL_M) {
              return null;
            } else {
              return this.returnNow();
            }
          }
          parseEscape() {
            if (this.char in escapes) {
              return this.return(escapes[this.char]);
            } else if (this.char === CHAR_u) {
              return this.call(this.parseSmallUnicode, this.parseUnicodeReturn);
            } else if (this.char === CHAR_U) {
              return this.call(this.parseLargeUnicode, this.parseUnicodeReturn);
            } else {
              throw this.error(new TomlError("Unknown escape character: " + this.char));
            }
          }
          parseUnicodeReturn(char) {
            try {
              const codePoint = parseInt(char, 16);
              if (codePoint >= SURROGATE_FIRST && codePoint <= SURROGATE_LAST) {
                throw this.error(new TomlError("Invalid unicode, character in range 0xD800 - 0xDFFF is reserved"));
              }
              return this.returnNow(String.fromCodePoint(codePoint));
            } catch (err) {
              throw this.error(TomlError.wrap(err));
            }
          }
          parseSmallUnicode() {
            if (!isHexit(this.char)) {
              throw this.error(new TomlError("Invalid character in unicode sequence, expected hex"));
            } else {
              this.consume();
              if (this.state.buf.length >= 4)
                return this.return();
            }
          }
          parseLargeUnicode() {
            if (!isHexit(this.char)) {
              throw this.error(new TomlError("Invalid character in unicode sequence, expected hex"));
            } else {
              this.consume();
              if (this.state.buf.length >= 8)
                return this.return();
            }
          }
          parseNumberSign() {
            this.consume();
            return this.next(this.parseMaybeSignedInfOrNan);
          }
          parseMaybeSignedInfOrNan() {
            if (this.char === CHAR_i) {
              return this.next(this.parseInf);
            } else if (this.char === CHAR_n) {
              return this.next(this.parseNan);
            } else {
              return this.callNow(this.parseNoUnder, this.parseNumberIntegerStart);
            }
          }
          parseNumberIntegerStart() {
            if (this.char === CHAR_0) {
              this.consume();
              return this.next(this.parseNumberIntegerExponentOrDecimal);
            } else {
              return this.goto(this.parseNumberInteger);
            }
          }
          parseNumberIntegerExponentOrDecimal() {
            if (this.char === CHAR_PERIOD) {
              this.consume();
              return this.call(this.parseNoUnder, this.parseNumberFloat);
            } else if (this.char === CHAR_E || this.char === CHAR_e) {
              this.consume();
              return this.next(this.parseNumberExponentSign);
            } else {
              return this.returnNow(Integer(this.state.buf));
            }
          }
          parseNumberInteger() {
            if (isDigit(this.char)) {
              this.consume();
            } else if (this.char === CHAR_LOWBAR) {
              return this.call(this.parseNoUnder);
            } else if (this.char === CHAR_E || this.char === CHAR_e) {
              this.consume();
              return this.next(this.parseNumberExponentSign);
            } else if (this.char === CHAR_PERIOD) {
              this.consume();
              return this.call(this.parseNoUnder, this.parseNumberFloat);
            } else {
              const result = Integer(this.state.buf);
              if (result.isNaN()) {
                throw this.error(new TomlError("Invalid number"));
              } else {
                return this.returnNow(result);
              }
            }
          }
          parseNoUnder() {
            if (this.char === CHAR_LOWBAR || this.char === CHAR_PERIOD || this.char === CHAR_E || this.char === CHAR_e) {
              throw this.error(new TomlError("Unexpected character, expected digit"));
            } else if (this.atEndOfWord()) {
              throw this.error(new TomlError("Incomplete number"));
            }
            return this.returnNow();
          }
          parseNoUnderHexOctBinLiteral() {
            if (this.char === CHAR_LOWBAR || this.char === CHAR_PERIOD) {
              throw this.error(new TomlError("Unexpected character, expected digit"));
            } else if (this.atEndOfWord()) {
              throw this.error(new TomlError("Incomplete number"));
            }
            return this.returnNow();
          }
          parseNumberFloat() {
            if (this.char === CHAR_LOWBAR) {
              return this.call(this.parseNoUnder, this.parseNumberFloat);
            } else if (isDigit(this.char)) {
              this.consume();
            } else if (this.char === CHAR_E || this.char === CHAR_e) {
              this.consume();
              return this.next(this.parseNumberExponentSign);
            } else {
              return this.returnNow(Float(this.state.buf));
            }
          }
          parseNumberExponentSign() {
            if (isDigit(this.char)) {
              return this.goto(this.parseNumberExponent);
            } else if (this.char === CHAR_HYPHEN || this.char === CHAR_PLUS) {
              this.consume();
              this.call(this.parseNoUnder, this.parseNumberExponent);
            } else {
              throw this.error(new TomlError("Unexpected character, expected -, + or digit"));
            }
          }
          parseNumberExponent() {
            if (isDigit(this.char)) {
              this.consume();
            } else if (this.char === CHAR_LOWBAR) {
              return this.call(this.parseNoUnder);
            } else {
              return this.returnNow(Float(this.state.buf));
            }
          }
          parseNumberOrDateTime() {
            if (this.char === CHAR_0) {
              this.consume();
              return this.next(this.parseNumberBaseOrDateTime);
            } else {
              return this.goto(this.parseNumberOrDateTimeOnly);
            }
          }
          parseNumberOrDateTimeOnly() {
            if (this.char === CHAR_LOWBAR) {
              return this.call(this.parseNoUnder, this.parseNumberInteger);
            } else if (isDigit(this.char)) {
              this.consume();
              if (this.state.buf.length > 4)
                this.next(this.parseNumberInteger);
            } else if (this.char === CHAR_E || this.char === CHAR_e) {
              this.consume();
              return this.next(this.parseNumberExponentSign);
            } else if (this.char === CHAR_PERIOD) {
              this.consume();
              return this.call(this.parseNoUnder, this.parseNumberFloat);
            } else if (this.char === CHAR_HYPHEN) {
              return this.goto(this.parseDateTime);
            } else if (this.char === CHAR_COLON) {
              return this.goto(this.parseOnlyTimeHour);
            } else {
              return this.returnNow(Integer(this.state.buf));
            }
          }
          parseDateTimeOnly() {
            if (this.state.buf.length < 4) {
              if (isDigit(this.char)) {
                return this.consume();
              } else if (this.char === CHAR_COLON) {
                return this.goto(this.parseOnlyTimeHour);
              } else {
                throw this.error(new TomlError("Expected digit while parsing year part of a date"));
              }
            } else {
              if (this.char === CHAR_HYPHEN) {
                return this.goto(this.parseDateTime);
              } else {
                throw this.error(new TomlError("Expected hyphen (-) while parsing year part of date"));
              }
            }
          }
          parseNumberBaseOrDateTime() {
            if (this.char === CHAR_b) {
              this.consume();
              return this.call(this.parseNoUnderHexOctBinLiteral, this.parseIntegerBin);
            } else if (this.char === CHAR_o) {
              this.consume();
              return this.call(this.parseNoUnderHexOctBinLiteral, this.parseIntegerOct);
            } else if (this.char === CHAR_x) {
              this.consume();
              return this.call(this.parseNoUnderHexOctBinLiteral, this.parseIntegerHex);
            } else if (this.char === CHAR_PERIOD) {
              return this.goto(this.parseNumberInteger);
            } else if (isDigit(this.char)) {
              return this.goto(this.parseDateTimeOnly);
            } else {
              return this.returnNow(Integer(this.state.buf));
            }
          }
          parseIntegerHex() {
            if (isHexit(this.char)) {
              this.consume();
            } else if (this.char === CHAR_LOWBAR) {
              return this.call(this.parseNoUnderHexOctBinLiteral);
            } else {
              const result = Integer(this.state.buf);
              if (result.isNaN()) {
                throw this.error(new TomlError("Invalid number"));
              } else {
                return this.returnNow(result);
              }
            }
          }
          parseIntegerOct() {
            if (isOctit(this.char)) {
              this.consume();
            } else if (this.char === CHAR_LOWBAR) {
              return this.call(this.parseNoUnderHexOctBinLiteral);
            } else {
              const result = Integer(this.state.buf);
              if (result.isNaN()) {
                throw this.error(new TomlError("Invalid number"));
              } else {
                return this.returnNow(result);
              }
            }
          }
          parseIntegerBin() {
            if (isBit(this.char)) {
              this.consume();
            } else if (this.char === CHAR_LOWBAR) {
              return this.call(this.parseNoUnderHexOctBinLiteral);
            } else {
              const result = Integer(this.state.buf);
              if (result.isNaN()) {
                throw this.error(new TomlError("Invalid number"));
              } else {
                return this.returnNow(result);
              }
            }
          }
          parseDateTime() {
            if (this.state.buf.length < 4) {
              throw this.error(new TomlError("Years less than 1000 must be zero padded to four characters"));
            }
            this.state.result = this.state.buf;
            this.state.buf = "";
            return this.next(this.parseDateMonth);
          }
          parseDateMonth() {
            if (this.char === CHAR_HYPHEN) {
              if (this.state.buf.length < 2) {
                throw this.error(new TomlError("Months less than 10 must be zero padded to two characters"));
              }
              this.state.result += "-" + this.state.buf;
              this.state.buf = "";
              return this.next(this.parseDateDay);
            } else if (isDigit(this.char)) {
              this.consume();
            } else {
              throw this.error(new TomlError("Incomplete datetime"));
            }
          }
          parseDateDay() {
            if (this.char === CHAR_T || this.char === CHAR_SP) {
              if (this.state.buf.length < 2) {
                throw this.error(new TomlError("Days less than 10 must be zero padded to two characters"));
              }
              this.state.result += "-" + this.state.buf;
              this.state.buf = "";
              return this.next(this.parseStartTimeHour);
            } else if (this.atEndOfWord()) {
              return this.returnNow(createDate(this.state.result + "-" + this.state.buf));
            } else if (isDigit(this.char)) {
              this.consume();
            } else {
              throw this.error(new TomlError("Incomplete datetime"));
            }
          }
          parseStartTimeHour() {
            if (this.atEndOfWord()) {
              return this.returnNow(createDate(this.state.result));
            } else {
              return this.goto(this.parseTimeHour);
            }
          }
          parseTimeHour() {
            if (this.char === CHAR_COLON) {
              if (this.state.buf.length < 2) {
                throw this.error(new TomlError("Hours less than 10 must be zero padded to two characters"));
              }
              this.state.result += "T" + this.state.buf;
              this.state.buf = "";
              return this.next(this.parseTimeMin);
            } else if (isDigit(this.char)) {
              this.consume();
            } else {
              throw this.error(new TomlError("Incomplete datetime"));
            }
          }
          parseTimeMin() {
            if (this.state.buf.length < 2 && isDigit(this.char)) {
              this.consume();
            } else if (this.state.buf.length === 2 && this.char === CHAR_COLON) {
              this.state.result += ":" + this.state.buf;
              this.state.buf = "";
              return this.next(this.parseTimeSec);
            } else {
              throw this.error(new TomlError("Incomplete datetime"));
            }
          }
          parseTimeSec() {
            if (isDigit(this.char)) {
              this.consume();
              if (this.state.buf.length === 2) {
                this.state.result += ":" + this.state.buf;
                this.state.buf = "";
                return this.next(this.parseTimeZoneOrFraction);
              }
            } else {
              throw this.error(new TomlError("Incomplete datetime"));
            }
          }
          parseOnlyTimeHour() {
            if (this.char === CHAR_COLON) {
              if (this.state.buf.length < 2) {
                throw this.error(new TomlError("Hours less than 10 must be zero padded to two characters"));
              }
              this.state.result = this.state.buf;
              this.state.buf = "";
              return this.next(this.parseOnlyTimeMin);
            } else {
              throw this.error(new TomlError("Incomplete time"));
            }
          }
          parseOnlyTimeMin() {
            if (this.state.buf.length < 2 && isDigit(this.char)) {
              this.consume();
            } else if (this.state.buf.length === 2 && this.char === CHAR_COLON) {
              this.state.result += ":" + this.state.buf;
              this.state.buf = "";
              return this.next(this.parseOnlyTimeSec);
            } else {
              throw this.error(new TomlError("Incomplete time"));
            }
          }
          parseOnlyTimeSec() {
            if (isDigit(this.char)) {
              this.consume();
              if (this.state.buf.length === 2) {
                return this.next(this.parseOnlyTimeFractionMaybe);
              }
            } else {
              throw this.error(new TomlError("Incomplete time"));
            }
          }
          parseOnlyTimeFractionMaybe() {
            this.state.result += ":" + this.state.buf;
            if (this.char === CHAR_PERIOD) {
              this.state.buf = "";
              this.next(this.parseOnlyTimeFraction);
            } else {
              return this.return(createTime(this.state.result));
            }
          }
          parseOnlyTimeFraction() {
            if (isDigit(this.char)) {
              this.consume();
            } else if (this.atEndOfWord()) {
              if (this.state.buf.length === 0)
                throw this.error(new TomlError("Expected digit in milliseconds"));
              return this.returnNow(createTime(this.state.result + "." + this.state.buf));
            } else {
              throw this.error(new TomlError("Unexpected character in datetime, expected period (.), minus (-), plus (+) or Z"));
            }
          }
          parseTimeZoneOrFraction() {
            if (this.char === CHAR_PERIOD) {
              this.consume();
              this.next(this.parseDateTimeFraction);
            } else if (this.char === CHAR_HYPHEN || this.char === CHAR_PLUS) {
              this.consume();
              this.next(this.parseTimeZoneHour);
            } else if (this.char === CHAR_Z) {
              this.consume();
              return this.return(createDateTime(this.state.result + this.state.buf));
            } else if (this.atEndOfWord()) {
              return this.returnNow(createDateTimeFloat(this.state.result + this.state.buf));
            } else {
              throw this.error(new TomlError("Unexpected character in datetime, expected period (.), minus (-), plus (+) or Z"));
            }
          }
          parseDateTimeFraction() {
            if (isDigit(this.char)) {
              this.consume();
            } else if (this.state.buf.length === 1) {
              throw this.error(new TomlError("Expected digit in milliseconds"));
            } else if (this.char === CHAR_HYPHEN || this.char === CHAR_PLUS) {
              this.consume();
              this.next(this.parseTimeZoneHour);
            } else if (this.char === CHAR_Z) {
              this.consume();
              return this.return(createDateTime(this.state.result + this.state.buf));
            } else if (this.atEndOfWord()) {
              return this.returnNow(createDateTimeFloat(this.state.result + this.state.buf));
            } else {
              throw this.error(new TomlError("Unexpected character in datetime, expected period (.), minus (-), plus (+) or Z"));
            }
          }
          parseTimeZoneHour() {
            if (isDigit(this.char)) {
              this.consume();
              if (/\d\d$/.test(this.state.buf))
                return this.next(this.parseTimeZoneSep);
            } else {
              throw this.error(new TomlError("Unexpected character in datetime, expected digit"));
            }
          }
          parseTimeZoneSep() {
            if (this.char === CHAR_COLON) {
              this.consume();
              this.next(this.parseTimeZoneMin);
            } else {
              throw this.error(new TomlError("Unexpected character in datetime, expected colon"));
            }
          }
          parseTimeZoneMin() {
            if (isDigit(this.char)) {
              this.consume();
              if (/\d\d$/.test(this.state.buf))
                return this.return(createDateTime(this.state.result + this.state.buf));
            } else {
              throw this.error(new TomlError("Unexpected character in datetime, expected digit"));
            }
          }
          parseBoolean() {
            if (this.char === CHAR_t) {
              this.consume();
              return this.next(this.parseTrue_r);
            } else if (this.char === CHAR_f) {
              this.consume();
              return this.next(this.parseFalse_a);
            }
          }
          parseTrue_r() {
            if (this.char === CHAR_r) {
              this.consume();
              return this.next(this.parseTrue_u);
            } else {
              throw this.error(new TomlError("Invalid boolean, expected true or false"));
            }
          }
          parseTrue_u() {
            if (this.char === CHAR_u) {
              this.consume();
              return this.next(this.parseTrue_e);
            } else {
              throw this.error(new TomlError("Invalid boolean, expected true or false"));
            }
          }
          parseTrue_e() {
            if (this.char === CHAR_e) {
              return this.return(true);
            } else {
              throw this.error(new TomlError("Invalid boolean, expected true or false"));
            }
          }
          parseFalse_a() {
            if (this.char === CHAR_a) {
              this.consume();
              return this.next(this.parseFalse_l);
            } else {
              throw this.error(new TomlError("Invalid boolean, expected true or false"));
            }
          }
          parseFalse_l() {
            if (this.char === CHAR_l) {
              this.consume();
              return this.next(this.parseFalse_s);
            } else {
              throw this.error(new TomlError("Invalid boolean, expected true or false"));
            }
          }
          parseFalse_s() {
            if (this.char === CHAR_s) {
              this.consume();
              return this.next(this.parseFalse_e);
            } else {
              throw this.error(new TomlError("Invalid boolean, expected true or false"));
            }
          }
          parseFalse_e() {
            if (this.char === CHAR_e) {
              return this.return(false);
            } else {
              throw this.error(new TomlError("Invalid boolean, expected true or false"));
            }
          }
          parseInlineList() {
            if (this.char === CHAR_SP || this.char === CTRL_I || this.char === CTRL_M || this.char === CTRL_J) {
              return null;
            } else if (this.char === Parser.END) {
              throw this.error(new TomlError("Unterminated inline array"));
            } else if (this.char === CHAR_NUM) {
              return this.call(this.parseComment);
            } else if (this.char === CHAR_RSQB) {
              return this.return(this.state.resultArr || InlineList());
            } else {
              return this.callNow(this.parseValue, this.recordInlineListValue);
            }
          }
          recordInlineListValue(value) {
            if (this.state.resultArr) {
              const listType = this.state.resultArr[_contentType];
              const valueType = tomlType(value);
              if (listType !== valueType) {
                throw this.error(new TomlError(`Inline lists must be a single type, not a mix of ${listType} and ${valueType}`));
              }
            } else {
              this.state.resultArr = InlineList(tomlType(value));
            }
            if (isFloat(value) || isInteger(value)) {
              this.state.resultArr.push(value.valueOf());
            } else {
              this.state.resultArr.push(value);
            }
            return this.goto(this.parseInlineListNext);
          }
          parseInlineListNext() {
            if (this.char === CHAR_SP || this.char === CTRL_I || this.char === CTRL_M || this.char === CTRL_J) {
              return null;
            } else if (this.char === CHAR_NUM) {
              return this.call(this.parseComment);
            } else if (this.char === CHAR_COMMA) {
              return this.next(this.parseInlineList);
            } else if (this.char === CHAR_RSQB) {
              return this.goto(this.parseInlineList);
            } else {
              throw this.error(new TomlError("Invalid character, expected whitespace, comma (,) or close bracket (])"));
            }
          }
          parseInlineTable() {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else if (this.char === Parser.END || this.char === CHAR_NUM || this.char === CTRL_J || this.char === CTRL_M) {
              throw this.error(new TomlError("Unterminated inline array"));
            } else if (this.char === CHAR_RCUB) {
              return this.return(this.state.resultTable || InlineTable());
            } else {
              if (!this.state.resultTable)
                this.state.resultTable = InlineTable();
              return this.callNow(this.parseAssign, this.recordInlineTableValue);
            }
          }
          recordInlineTableValue(kv) {
            let target = this.state.resultTable;
            let finalKey = kv.key.pop();
            for (let kw of kv.key) {
              if (hasKey(target, kw) && (!isTable(target[kw]) || target[kw][_declared])) {
                throw this.error(new TomlError("Can't redefine existing key"));
              }
              target = target[kw] = target[kw] || Table();
            }
            if (hasKey(target, finalKey)) {
              throw this.error(new TomlError("Can't redefine existing key"));
            }
            if (isInteger(kv.value) || isFloat(kv.value)) {
              target[finalKey] = kv.value.valueOf();
            } else {
              target[finalKey] = kv.value;
            }
            return this.goto(this.parseInlineTableNext);
          }
          parseInlineTableNext() {
            if (this.char === CHAR_SP || this.char === CTRL_I) {
              return null;
            } else if (this.char === Parser.END || this.char === CHAR_NUM || this.char === CTRL_J || this.char === CTRL_M) {
              throw this.error(new TomlError("Unterminated inline array"));
            } else if (this.char === CHAR_COMMA) {
              return this.next(this.parseInlineTable);
            } else if (this.char === CHAR_RCUB) {
              return this.goto(this.parseInlineTable);
            } else {
              throw this.error(new TomlError("Invalid character, expected whitespace, comma (,) or close bracket (])"));
            }
          }
        }
        return TOMLParser;
      }
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-pretty-error.js
  var require_parse_pretty_error = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-pretty-error.js"(exports2, module2) {
      "use strict";
      module2.exports = prettyError;
      function prettyError(err, buf) {
        if (err.pos == null || err.line == null)
          return err;
        let msg = err.message;
        msg += ` at row ${err.line + 1}, col ${err.col + 1}, pos ${err.pos}:
`;
        if (buf && buf.split) {
          const lines = buf.split(/\n/);
          const lineNumWidth = String(Math.min(lines.length, err.line + 3)).length;
          let linePadding = " ";
          while (linePadding.length < lineNumWidth)
            linePadding += " ";
          for (let ii = Math.max(0, err.line - 1); ii < Math.min(lines.length, err.line + 2); ++ii) {
            let lineNum = String(ii + 1);
            if (lineNum.length < lineNumWidth)
              lineNum = " " + lineNum;
            if (err.line === ii) {
              msg += lineNum + "> " + lines[ii] + "\n";
              msg += linePadding + "  ";
              for (let hh = 0; hh < err.col; ++hh) {
                msg += " ";
              }
              msg += "^\n";
            } else {
              msg += lineNum + ": " + lines[ii] + "\n";
            }
          }
        }
        err.message = msg + "\n";
        return err;
      }
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-string.js
  var require_parse_string = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-string.js"(exports2, module2) {
      "use strict";
      module2.exports = parseString;
      var TOMLParser = require_toml_parser();
      var prettyError = require_parse_pretty_error();
      function parseString(str) {
        if (global.Buffer && global.Buffer.isBuffer(str)) {
          str = str.toString("utf8");
        }
        const parser = new TOMLParser();
        try {
          parser.parse(str);
          return parser.finish();
        } catch (err) {
          throw prettyError(err, str);
        }
      }
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-async.js
  var require_parse_async = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-async.js"(exports2, module2) {
      "use strict";
      module2.exports = parseAsync;
      var TOMLParser = require_toml_parser();
      var prettyError = require_parse_pretty_error();
      function parseAsync(str, opts) {
        if (!opts)
          opts = {};
        const index = 0;
        const blocksize = opts.blocksize || 40960;
        const parser = new TOMLParser();
        return new Promise((resolve2, reject) => {
          setImmediate(parseAsyncNext, index, blocksize, resolve2, reject);
        });
        function parseAsyncNext(index2, blocksize2, resolve2, reject) {
          if (index2 >= str.length) {
            try {
              return resolve2(parser.finish());
            } catch (err) {
              return reject(prettyError(err, str));
            }
          }
          try {
            parser.parse(str.slice(index2, index2 + blocksize2));
            setImmediate(parseAsyncNext, index2 + blocksize2, blocksize2, resolve2, reject);
          } catch (err) {
            reject(prettyError(err, str));
          }
        }
      }
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-stream.js
  var require_parse_stream = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse-stream.js"(exports2, module2) {
      "use strict";
      module2.exports = parseStream;
      var stream = __require("stream");
      var TOMLParser = require_toml_parser();
      function parseStream(stm) {
        if (stm) {
          return parseReadable(stm);
        } else {
          return parseTransform(stm);
        }
      }
      function parseReadable(stm) {
        const parser = new TOMLParser();
        stm.setEncoding("utf8");
        return new Promise((resolve2, reject) => {
          let readable;
          let ended = false;
          let errored = false;
          function finish() {
            ended = true;
            if (readable)
              return;
            try {
              resolve2(parser.finish());
            } catch (err) {
              reject(err);
            }
          }
          function error(err) {
            errored = true;
            reject(err);
          }
          stm.once("end", finish);
          stm.once("error", error);
          readNext();
          function readNext() {
            readable = true;
            let data;
            while ((data = stm.read()) !== null) {
              try {
                parser.parse(data);
              } catch (err) {
                return error(err);
              }
            }
            readable = false;
            if (ended)
              return finish();
            if (errored)
              return;
            stm.once("readable", readNext);
          }
        });
      }
      function parseTransform() {
        const parser = new TOMLParser();
        return new stream.Transform({
          objectMode: true,
          transform(chunk, encoding, cb) {
            try {
              parser.parse(chunk.toString(encoding));
            } catch (err) {
              this.emit("error", err);
            }
            cb();
          },
          flush(cb) {
            try {
              this.push(parser.finish());
            } catch (err) {
              this.emit("error", err);
            }
            cb();
          }
        });
      }
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse.js
  var require_parse = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/parse.js"(exports2, module2) {
      "use strict";
      module2.exports = require_parse_string();
      module2.exports.async = require_parse_async();
      module2.exports.stream = require_parse_stream();
      module2.exports.prettyError = require_parse_pretty_error();
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/stringify.js
  var require_stringify = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/stringify.js"(exports2, module2) {
      "use strict";
      module2.exports = stringify;
      module2.exports.value = stringifyInline;
      function stringify(obj) {
        if (obj === null)
          throw typeError("null");
        if (obj === void 0)
          throw typeError("undefined");
        if (typeof obj !== "object")
          throw typeError(typeof obj);
        if (typeof obj.toJSON === "function")
          obj = obj.toJSON();
        if (obj == null)
          return null;
        const type = tomlType2(obj);
        if (type !== "table")
          throw typeError(type);
        return stringifyObject("", "", obj);
      }
      function typeError(type) {
        return new Error("Can only stringify objects, not " + type);
      }
      function arrayOneTypeError() {
        return new Error("Array values can't have mixed types");
      }
      function getInlineKeys(obj) {
        return Object.keys(obj).filter((key) => isInline(obj[key]));
      }
      function getComplexKeys(obj) {
        return Object.keys(obj).filter((key) => !isInline(obj[key]));
      }
      function toJSON(obj) {
        let nobj = Array.isArray(obj) ? [] : Object.prototype.hasOwnProperty.call(obj, "__proto__") ? { ["__proto__"]: void 0 } : {};
        for (let prop of Object.keys(obj)) {
          if (obj[prop] && typeof obj[prop].toJSON === "function" && !("toISOString" in obj[prop])) {
            nobj[prop] = obj[prop].toJSON();
          } else {
            nobj[prop] = obj[prop];
          }
        }
        return nobj;
      }
      function stringifyObject(prefix, indent, obj) {
        obj = toJSON(obj);
        var inlineKeys;
        var complexKeys;
        inlineKeys = getInlineKeys(obj);
        complexKeys = getComplexKeys(obj);
        var result = [];
        var inlineIndent = indent || "";
        inlineKeys.forEach((key) => {
          var type = tomlType2(obj[key]);
          if (type !== "undefined" && type !== "null") {
            result.push(inlineIndent + stringifyKey(key) + " = " + stringifyAnyInline(obj[key], true));
          }
        });
        if (result.length > 0)
          result.push("");
        var complexIndent = prefix && inlineKeys.length > 0 ? indent + "  " : "";
        complexKeys.forEach((key) => {
          result.push(stringifyComplex(prefix, complexIndent, key, obj[key]));
        });
        return result.join("\n");
      }
      function isInline(value) {
        switch (tomlType2(value)) {
          case "undefined":
          case "null":
          case "integer":
          case "nan":
          case "float":
          case "boolean":
          case "string":
          case "datetime":
            return true;
          case "array":
            return value.length === 0 || tomlType2(value[0]) !== "table";
          case "table":
            return Object.keys(value).length === 0;
          default:
            return false;
        }
      }
      function tomlType2(value) {
        if (value === void 0) {
          return "undefined";
        } else if (value === null) {
          return "null";
        } else if (typeof value === "bigint" || Number.isInteger(value) && !Object.is(value, -0)) {
          return "integer";
        } else if (typeof value === "number") {
          return "float";
        } else if (typeof value === "boolean") {
          return "boolean";
        } else if (typeof value === "string") {
          return "string";
        } else if ("toISOString" in value) {
          return isNaN(value) ? "undefined" : "datetime";
        } else if (Array.isArray(value)) {
          return "array";
        } else {
          return "table";
        }
      }
      function stringifyKey(key) {
        var keyStr = String(key);
        if (/^[-A-Za-z0-9_]+$/.test(keyStr)) {
          return keyStr;
        } else {
          return stringifyBasicString(keyStr);
        }
      }
      function stringifyBasicString(str) {
        return '"' + escapeString(str).replace(/"/g, '\\"') + '"';
      }
      function stringifyLiteralString(str) {
        return "'" + str + "'";
      }
      function numpad(num, str) {
        while (str.length < num)
          str = "0" + str;
        return str;
      }
      function escapeString(str) {
        return str.replace(/\\/g, "\\\\").replace(/[\b]/g, "\\b").replace(/\t/g, "\\t").replace(/\n/g, "\\n").replace(/\f/g, "\\f").replace(/\r/g, "\\r").replace(/([\u0000-\u001f\u007f])/, (c) => "\\u" + numpad(4, c.codePointAt(0).toString(16)));
      }
      function stringifyMultilineString(str) {
        let escaped = str.split(/\n/).map((str2) => {
          return escapeString(str2).replace(/"(?="")/g, '\\"');
        }).join("\n");
        if (escaped.slice(-1) === '"')
          escaped += "\\\n";
        return '"""\n' + escaped + '"""';
      }
      function stringifyAnyInline(value, multilineOk) {
        let type = tomlType2(value);
        if (type === "string") {
          if (multilineOk && /\n/.test(value)) {
            type = "string-multiline";
          } else if (!/[\b\t\n\f\r']/.test(value) && /"/.test(value)) {
            type = "string-literal";
          }
        }
        return stringifyInline(value, type);
      }
      function stringifyInline(value, type) {
        if (!type)
          type = tomlType2(value);
        switch (type) {
          case "string-multiline":
            return stringifyMultilineString(value);
          case "string":
            return stringifyBasicString(value);
          case "string-literal":
            return stringifyLiteralString(value);
          case "integer":
            return stringifyInteger(value);
          case "float":
            return stringifyFloat(value);
          case "boolean":
            return stringifyBoolean(value);
          case "datetime":
            return stringifyDatetime(value);
          case "array":
            return stringifyInlineArray(value.filter((_) => tomlType2(_) !== "null" && tomlType2(_) !== "undefined" && tomlType2(_) !== "nan"));
          case "table":
            return stringifyInlineTable(value);
          default:
            throw typeError(type);
        }
      }
      function stringifyInteger(value) {
        return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, "_");
      }
      function stringifyFloat(value) {
        if (value === Infinity) {
          return "inf";
        } else if (value === -Infinity) {
          return "-inf";
        } else if (Object.is(value, NaN)) {
          return "nan";
        } else if (Object.is(value, -0)) {
          return "-0.0";
        }
        var chunks = String(value).split(".");
        var int = chunks[0];
        var dec = chunks[1] || 0;
        return stringifyInteger(int) + "." + dec;
      }
      function stringifyBoolean(value) {
        return String(value);
      }
      function stringifyDatetime(value) {
        return value.toISOString();
      }
      function isNumber(type) {
        return type === "float" || type === "integer";
      }
      function arrayType(values) {
        var contentType = tomlType2(values[0]);
        if (values.every((_) => tomlType2(_) === contentType))
          return contentType;
        if (values.every((_) => isNumber(tomlType2(_))))
          return "float";
        return "mixed";
      }
      function validateArray(values) {
        const type = arrayType(values);
        if (type === "mixed") {
          throw arrayOneTypeError();
        }
        return type;
      }
      function stringifyInlineArray(values) {
        values = toJSON(values);
        const type = validateArray(values);
        var result = "[";
        var stringified = values.map((_) => stringifyInline(_, type));
        if (stringified.join(", ").length > 60 || /\n/.test(stringified)) {
          result += "\n  " + stringified.join(",\n  ") + "\n";
        } else {
          result += " " + stringified.join(", ") + (stringified.length > 0 ? " " : "");
        }
        return result + "]";
      }
      function stringifyInlineTable(value) {
        value = toJSON(value);
        var result = [];
        Object.keys(value).forEach((key) => {
          result.push(stringifyKey(key) + " = " + stringifyAnyInline(value[key], false));
        });
        return "{ " + result.join(", ") + (result.length > 0 ? " " : "") + "}";
      }
      function stringifyComplex(prefix, indent, key, value) {
        var valueType = tomlType2(value);
        if (valueType === "array") {
          return stringifyArrayOfTables(prefix, indent, key, value);
        } else if (valueType === "table") {
          return stringifyComplexTable(prefix, indent, key, value);
        } else {
          throw typeError(valueType);
        }
      }
      function stringifyArrayOfTables(prefix, indent, key, values) {
        values = toJSON(values);
        validateArray(values);
        var firstValueType = tomlType2(values[0]);
        if (firstValueType !== "table")
          throw typeError(firstValueType);
        var fullKey = prefix + stringifyKey(key);
        var result = "";
        values.forEach((table) => {
          if (result.length > 0)
            result += "\n";
          result += indent + "[[" + fullKey + "]]\n";
          result += stringifyObject(fullKey + ".", indent, table);
        });
        return result;
      }
      function stringifyComplexTable(prefix, indent, key, value) {
        var fullKey = prefix + stringifyKey(key);
        var result = "";
        if (getInlineKeys(value).length > 0) {
          result += indent + "[" + fullKey + "]\n";
        }
        return result + stringifyObject(fullKey + ".", indent, value);
      }
    }
  });

  // ../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/toml.js
  var require_toml = __commonJS({
    "../../../.yarn/cache/@iarna-toml-npm-2.2.5-6da1399e8e-b61426dc1a.zip/node_modules/@iarna/toml/toml.js"(exports2) {
      "use strict";
      exports2.parse = require_parse();
      exports2.stringify = require_stringify();
    }
  });

  // ../../../.yarn/cache/eastasianwidth-npm-0.2.0-c37eb16bd1-9b1d3e1bae.zip/node_modules/eastasianwidth/eastasianwidth.js
  var require_eastasianwidth = __commonJS({
    "../../../.yarn/cache/eastasianwidth-npm-0.2.0-c37eb16bd1-9b1d3e1bae.zip/node_modules/eastasianwidth/eastasianwidth.js"(exports2, module2) {
      var eaw = {};
      if ("undefined" == typeof module2) {
        window.eastasianwidth = eaw;
      } else {
        module2.exports = eaw;
      }
      eaw.eastAsianWidth = function(character) {
        var x = character.charCodeAt(0);
        var y = character.length == 2 ? character.charCodeAt(1) : 0;
        var codePoint = x;
        if (55296 <= x && x <= 56319 && (56320 <= y && y <= 57343)) {
          x &= 1023;
          y &= 1023;
          codePoint = x << 10 | y;
          codePoint += 65536;
        }
        if (12288 == codePoint || 65281 <= codePoint && codePoint <= 65376 || 65504 <= codePoint && codePoint <= 65510) {
          return "F";
        }
        if (8361 == codePoint || 65377 <= codePoint && codePoint <= 65470 || 65474 <= codePoint && codePoint <= 65479 || 65482 <= codePoint && codePoint <= 65487 || 65490 <= codePoint && codePoint <= 65495 || 65498 <= codePoint && codePoint <= 65500 || 65512 <= codePoint && codePoint <= 65518) {
          return "H";
        }
        if (4352 <= codePoint && codePoint <= 4447 || 4515 <= codePoint && codePoint <= 4519 || 4602 <= codePoint && codePoint <= 4607 || 9001 <= codePoint && codePoint <= 9002 || 11904 <= codePoint && codePoint <= 11929 || 11931 <= codePoint && codePoint <= 12019 || 12032 <= codePoint && codePoint <= 12245 || 12272 <= codePoint && codePoint <= 12283 || 12289 <= codePoint && codePoint <= 12350 || 12353 <= codePoint && codePoint <= 12438 || 12441 <= codePoint && codePoint <= 12543 || 12549 <= codePoint && codePoint <= 12589 || 12593 <= codePoint && codePoint <= 12686 || 12688 <= codePoint && codePoint <= 12730 || 12736 <= codePoint && codePoint <= 12771 || 12784 <= codePoint && codePoint <= 12830 || 12832 <= codePoint && codePoint <= 12871 || 12880 <= codePoint && codePoint <= 13054 || 13056 <= codePoint && codePoint <= 19903 || 19968 <= codePoint && codePoint <= 42124 || 42128 <= codePoint && codePoint <= 42182 || 43360 <= codePoint && codePoint <= 43388 || 44032 <= codePoint && codePoint <= 55203 || 55216 <= codePoint && codePoint <= 55238 || 55243 <= codePoint && codePoint <= 55291 || 63744 <= codePoint && codePoint <= 64255 || 65040 <= codePoint && codePoint <= 65049 || 65072 <= codePoint && codePoint <= 65106 || 65108 <= codePoint && codePoint <= 65126 || 65128 <= codePoint && codePoint <= 65131 || 110592 <= codePoint && codePoint <= 110593 || 127488 <= codePoint && codePoint <= 127490 || 127504 <= codePoint && codePoint <= 127546 || 127552 <= codePoint && codePoint <= 127560 || 127568 <= codePoint && codePoint <= 127569 || 131072 <= codePoint && codePoint <= 194367 || 177984 <= codePoint && codePoint <= 196605 || 196608 <= codePoint && codePoint <= 262141) {
          return "W";
        }
        if (32 <= codePoint && codePoint <= 126 || 162 <= codePoint && codePoint <= 163 || 165 <= codePoint && codePoint <= 166 || 172 == codePoint || 175 == codePoint || 10214 <= codePoint && codePoint <= 10221 || 10629 <= codePoint && codePoint <= 10630) {
          return "Na";
        }
        if (161 == codePoint || 164 == codePoint || 167 <= codePoint && codePoint <= 168 || 170 == codePoint || 173 <= codePoint && codePoint <= 174 || 176 <= codePoint && codePoint <= 180 || 182 <= codePoint && codePoint <= 186 || 188 <= codePoint && codePoint <= 191 || 198 == codePoint || 208 == codePoint || 215 <= codePoint && codePoint <= 216 || 222 <= codePoint && codePoint <= 225 || 230 == codePoint || 232 <= codePoint && codePoint <= 234 || 236 <= codePoint && codePoint <= 237 || 240 == codePoint || 242 <= codePoint && codePoint <= 243 || 247 <= codePoint && codePoint <= 250 || 252 == codePoint || 254 == codePoint || 257 == codePoint || 273 == codePoint || 275 == codePoint || 283 == codePoint || 294 <= codePoint && codePoint <= 295 || 299 == codePoint || 305 <= codePoint && codePoint <= 307 || 312 == codePoint || 319 <= codePoint && codePoint <= 322 || 324 == codePoint || 328 <= codePoint && codePoint <= 331 || 333 == codePoint || 338 <= codePoint && codePoint <= 339 || 358 <= codePoint && codePoint <= 359 || 363 == codePoint || 462 == codePoint || 464 == codePoint || 466 == codePoint || 468 == codePoint || 470 == codePoint || 472 == codePoint || 474 == codePoint || 476 == codePoint || 593 == codePoint || 609 == codePoint || 708 == codePoint || 711 == codePoint || 713 <= codePoint && codePoint <= 715 || 717 == codePoint || 720 == codePoint || 728 <= codePoint && codePoint <= 731 || 733 == codePoint || 735 == codePoint || 768 <= codePoint && codePoint <= 879 || 913 <= codePoint && codePoint <= 929 || 931 <= codePoint && codePoint <= 937 || 945 <= codePoint && codePoint <= 961 || 963 <= codePoint && codePoint <= 969 || 1025 == codePoint || 1040 <= codePoint && codePoint <= 1103 || 1105 == codePoint || 8208 == codePoint || 8211 <= codePoint && codePoint <= 8214 || 8216 <= codePoint && codePoint <= 8217 || 8220 <= codePoint && codePoint <= 8221 || 8224 <= codePoint && codePoint <= 8226 || 8228 <= codePoint && codePoint <= 8231 || 8240 == codePoint || 8242 <= codePoint && codePoint <= 8243 || 8245 == codePoint || 8251 == codePoint || 8254 == codePoint || 8308 == codePoint || 8319 == codePoint || 8321 <= codePoint && codePoint <= 8324 || 8364 == codePoint || 8451 == codePoint || 8453 == codePoint || 8457 == codePoint || 8467 == codePoint || 8470 == codePoint || 8481 <= codePoint && codePoint <= 8482 || 8486 == codePoint || 8491 == codePoint || 8531 <= codePoint && codePoint <= 8532 || 8539 <= codePoint && codePoint <= 8542 || 8544 <= codePoint && codePoint <= 8555 || 8560 <= codePoint && codePoint <= 8569 || 8585 == codePoint || 8592 <= codePoint && codePoint <= 8601 || 8632 <= codePoint && codePoint <= 8633 || 8658 == codePoint || 8660 == codePoint || 8679 == codePoint || 8704 == codePoint || 8706 <= codePoint && codePoint <= 8707 || 8711 <= codePoint && codePoint <= 8712 || 8715 == codePoint || 8719 == codePoint || 8721 == codePoint || 8725 == codePoint || 8730 == codePoint || 8733 <= codePoint && codePoint <= 8736 || 8739 == codePoint || 8741 == codePoint || 8743 <= codePoint && codePoint <= 8748 || 8750 == codePoint || 8756 <= codePoint && codePoint <= 8759 || 8764 <= codePoint && codePoint <= 8765 || 8776 == codePoint || 8780 == codePoint || 8786 == codePoint || 8800 <= codePoint && codePoint <= 8801 || 8804 <= codePoint && codePoint <= 8807 || 8810 <= codePoint && codePoint <= 8811 || 8814 <= codePoint && codePoint <= 8815 || 8834 <= codePoint && codePoint <= 8835 || 8838 <= codePoint && codePoint <= 8839 || 8853 == codePoint || 8857 == codePoint || 8869 == codePoint || 8895 == codePoint || 8978 == codePoint || 9312 <= codePoint && codePoint <= 9449 || 9451 <= codePoint && codePoint <= 9547 || 9552 <= codePoint && codePoint <= 9587 || 9600 <= codePoint && codePoint <= 9615 || 9618 <= codePoint && codePoint <= 9621 || 9632 <= codePoint && codePoint <= 9633 || 9635 <= codePoint && codePoint <= 9641 || 9650 <= codePoint && codePoint <= 9651 || 9654 <= codePoint && codePoint <= 9655 || 9660 <= codePoint && codePoint <= 9661 || 9664 <= codePoint && codePoint <= 9665 || 9670 <= codePoint && codePoint <= 9672 || 9675 == codePoint || 9678 <= codePoint && codePoint <= 9681 || 9698 <= codePoint && codePoint <= 9701 || 9711 == codePoint || 9733 <= codePoint && codePoint <= 9734 || 9737 == codePoint || 9742 <= codePoint && codePoint <= 9743 || 9748 <= codePoint && codePoint <= 9749 || 9756 == codePoint || 9758 == codePoint || 9792 == codePoint || 9794 == codePoint || 9824 <= codePoint && codePoint <= 9825 || 9827 <= codePoint && codePoint <= 9829 || 9831 <= codePoint && codePoint <= 9834 || 9836 <= codePoint && codePoint <= 9837 || 9839 == codePoint || 9886 <= codePoint && codePoint <= 9887 || 9918 <= codePoint && codePoint <= 9919 || 9924 <= codePoint && codePoint <= 9933 || 9935 <= codePoint && codePoint <= 9953 || 9955 == codePoint || 9960 <= codePoint && codePoint <= 9983 || 10045 == codePoint || 10071 == codePoint || 10102 <= codePoint && codePoint <= 10111 || 11093 <= codePoint && codePoint <= 11097 || 12872 <= codePoint && codePoint <= 12879 || 57344 <= codePoint && codePoint <= 63743 || 65024 <= codePoint && codePoint <= 65039 || 65533 == codePoint || 127232 <= codePoint && codePoint <= 127242 || 127248 <= codePoint && codePoint <= 127277 || 127280 <= codePoint && codePoint <= 127337 || 127344 <= codePoint && codePoint <= 127386 || 917760 <= codePoint && codePoint <= 917999 || 983040 <= codePoint && codePoint <= 1048573 || 1048576 <= codePoint && codePoint <= 1114109) {
          return "A";
        }
        return "N";
      };
      eaw.characterLength = function(character) {
        var code = this.eastAsianWidth(character);
        if (code == "F" || code == "W" || code == "A") {
          return 2;
        } else {
          return 1;
        }
      };
      function stringToArray(string) {
        return string.match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\uD800-\uDFFF]/g) || [];
      }
      eaw.length = function(string) {
        var characters = stringToArray(string);
        var len = 0;
        for (var i = 0; i < characters.length; i++) {
          len = len + this.characterLength(characters[i]);
        }
        return len;
      };
      eaw.slice = function(text, start, end) {
        textLen = eaw.length(text);
        start = start ? start : 0;
        end = end ? end : 1;
        if (start < 0) {
          start = textLen + start;
        }
        if (end < 0) {
          end = textLen + end;
        }
        var result = "";
        var eawLen = 0;
        var chars = stringToArray(text);
        for (var i = 0; i < chars.length; i++) {
          var char = chars[i];
          var charLen = eaw.length(char);
          if (eawLen >= start - (charLen == 2 ? 1 : 0)) {
            if (eawLen + charLen <= end) {
              result += char;
            } else {
              break;
            }
          }
          eawLen += charLen;
        }
        return result;
      };
    }
  });

  // ../../../.yarn/cache/emoji-regex-npm-9.2.2-e6fac8d058-915acf859c.zip/node_modules/emoji-regex/index.js
  var require_emoji_regex = __commonJS({
    "../../../.yarn/cache/emoji-regex-npm-9.2.2-e6fac8d058-915acf859c.zip/node_modules/emoji-regex/index.js"(exports2, module2) {
      "use strict";
      module2.exports = function() {
        return /\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62(?:\uDB40\uDC77\uDB40\uDC6C\uDB40\uDC73|\uDB40\uDC73\uDB40\uDC63\uDB40\uDC74|\uDB40\uDC65\uDB40\uDC6E\uDB40\uDC67)\uDB40\uDC7F|(?:\uD83E\uDDD1\uD83C\uDFFF\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFF\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB-\uDFFE])|(?:\uD83E\uDDD1\uD83C\uDFFE\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFE\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB-\uDFFD\uDFFF])|(?:\uD83E\uDDD1\uD83C\uDFFD\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFD\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB\uDFFC\uDFFE\uDFFF])|(?:\uD83E\uDDD1\uD83C\uDFFC\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFC\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB\uDFFD-\uDFFF])|(?:\uD83E\uDDD1\uD83C\uDFFB\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFB\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFC-\uDFFF])|\uD83D\uDC68(?:\uD83C\uDFFB(?:\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF]))|\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFC-\uDFFF])|[\u2695\u2696\u2708]\uFE0F|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD]))?|(?:\uD83C[\uDFFC-\uDFFF])\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF]))|\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83D\uDC68|(?:\uD83D[\uDC68\uDC69])\u200D(?:\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67]))|\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFE])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFE\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFD\uDFFF])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB\uDFFC\uDFFE\uDFFF])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFC\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB\uDFFD-\uDFFF])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|(?:\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708]|\u200D[\u2695\u2696\u2708])\uFE0F|\u200D(?:(?:\uD83D[\uDC68\uDC69])\u200D(?:\uD83D[\uDC66\uDC67])|\uD83D[\uDC66\uDC67])|\uD83C\uDFFF|\uD83C\uDFFE|\uD83C\uDFFD|\uD83C\uDFFC)?|(?:\uD83D\uDC69(?:\uD83C\uDFFB\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D(?:\uD83D[\uDC68\uDC69])|\uD83D[\uDC68\uDC69])|(?:\uD83C[\uDFFC-\uDFFF])\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D(?:\uD83D[\uDC68\uDC69])|\uD83D[\uDC68\uDC69]))|\uD83E\uDDD1(?:\uD83C[\uDFFB-\uDFFF])\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1)(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC69\u200D\uD83D\uDC69\u200D(?:\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67]))|\uD83D\uDC69(?:\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D(?:\uD83D[\uDC68\uDC69])|\uD83D[\uDC68\uDC69])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFE\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFC\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFB\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD]))|\uD83E\uDDD1(?:\u200D(?:\uD83E\uDD1D\u200D\uD83E\uDDD1|\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFE\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFC\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFB\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD]))|\uD83D\uDC69\u200D\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC69\u200D\uD83D\uDC69\u200D(?:\uD83D[\uDC66\uDC67])|\uD83D\uDC69\u200D\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67])|(?:\uD83D\uDC41\uFE0F\u200D\uD83D\uDDE8|\uD83E\uDDD1(?:\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708]|\uD83C\uDFFB\u200D[\u2695\u2696\u2708]|\u200D[\u2695\u2696\u2708])|\uD83D\uDC69(?:\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708]|\uD83C\uDFFB\u200D[\u2695\u2696\u2708]|\u200D[\u2695\u2696\u2708])|\uD83D\uDE36\u200D\uD83C\uDF2B|\uD83C\uDFF3\uFE0F\u200D\u26A7|\uD83D\uDC3B\u200D\u2744|(?:(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD])(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC6F|\uD83E[\uDD3C\uDDDE\uDDDF])\u200D[\u2640\u2642]|(?:\u26F9|\uD83C[\uDFCB\uDFCC]|\uD83D\uDD75)(?:\uFE0F|\uD83C[\uDFFB-\uDFFF])\u200D[\u2640\u2642]|\uD83C\uDFF4\u200D\u2620|(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD])\u200D[\u2640\u2642]|[\xA9\xAE\u203C\u2049\u2122\u2139\u2194-\u2199\u21A9\u21AA\u2328\u23CF\u23ED-\u23EF\u23F1\u23F2\u23F8-\u23FA\u24C2\u25AA\u25AB\u25B6\u25C0\u25FB\u25FC\u2600-\u2604\u260E\u2611\u2618\u2620\u2622\u2623\u2626\u262A\u262E\u262F\u2638-\u263A\u2640\u2642\u265F\u2660\u2663\u2665\u2666\u2668\u267B\u267E\u2692\u2694-\u2697\u2699\u269B\u269C\u26A0\u26A7\u26B0\u26B1\u26C8\u26CF\u26D1\u26D3\u26E9\u26F0\u26F1\u26F4\u26F7\u26F8\u2702\u2708\u2709\u270F\u2712\u2714\u2716\u271D\u2721\u2733\u2734\u2744\u2747\u2763\u27A1\u2934\u2935\u2B05-\u2B07\u3030\u303D\u3297\u3299]|\uD83C[\uDD70\uDD71\uDD7E\uDD7F\uDE02\uDE37\uDF21\uDF24-\uDF2C\uDF36\uDF7D\uDF96\uDF97\uDF99-\uDF9B\uDF9E\uDF9F\uDFCD\uDFCE\uDFD4-\uDFDF\uDFF5\uDFF7]|\uD83D[\uDC3F\uDCFD\uDD49\uDD4A\uDD6F\uDD70\uDD73\uDD76-\uDD79\uDD87\uDD8A-\uDD8D\uDDA5\uDDA8\uDDB1\uDDB2\uDDBC\uDDC2-\uDDC4\uDDD1-\uDDD3\uDDDC-\uDDDE\uDDE1\uDDE3\uDDE8\uDDEF\uDDF3\uDDFA\uDECB\uDECD-\uDECF\uDEE0-\uDEE5\uDEE9\uDEF0\uDEF3])\uFE0F|\uD83C\uDFF3\uFE0F\u200D\uD83C\uDF08|\uD83D\uDC69\u200D\uD83D\uDC67|\uD83D\uDC69\u200D\uD83D\uDC66|\uD83D\uDE35\u200D\uD83D\uDCAB|\uD83D\uDE2E\u200D\uD83D\uDCA8|\uD83D\uDC15\u200D\uD83E\uDDBA|\uD83E\uDDD1(?:\uD83C\uDFFF|\uD83C\uDFFE|\uD83C\uDFFD|\uD83C\uDFFC|\uD83C\uDFFB)?|\uD83D\uDC69(?:\uD83C\uDFFF|\uD83C\uDFFE|\uD83C\uDFFD|\uD83C\uDFFC|\uD83C\uDFFB)?|\uD83C\uDDFD\uD83C\uDDF0|\uD83C\uDDF6\uD83C\uDDE6|\uD83C\uDDF4\uD83C\uDDF2|\uD83D\uDC08\u200D\u2B1B|\u2764\uFE0F\u200D(?:\uD83D\uDD25|\uD83E\uDE79)|\uD83D\uDC41\uFE0F|\uD83C\uDFF3\uFE0F|\uD83C\uDDFF(?:\uD83C[\uDDE6\uDDF2\uDDFC])|\uD83C\uDDFE(?:\uD83C[\uDDEA\uDDF9])|\uD83C\uDDFC(?:\uD83C[\uDDEB\uDDF8])|\uD83C\uDDFB(?:\uD83C[\uDDE6\uDDE8\uDDEA\uDDEC\uDDEE\uDDF3\uDDFA])|\uD83C\uDDFA(?:\uD83C[\uDDE6\uDDEC\uDDF2\uDDF3\uDDF8\uDDFE\uDDFF])|\uD83C\uDDF9(?:\uD83C[\uDDE6\uDDE8\uDDE9\uDDEB-\uDDED\uDDEF-\uDDF4\uDDF7\uDDF9\uDDFB\uDDFC\uDDFF])|\uD83C\uDDF8(?:\uD83C[\uDDE6-\uDDEA\uDDEC-\uDDF4\uDDF7-\uDDF9\uDDFB\uDDFD-\uDDFF])|\uD83C\uDDF7(?:\uD83C[\uDDEA\uDDF4\uDDF8\uDDFA\uDDFC])|\uD83C\uDDF5(?:\uD83C[\uDDE6\uDDEA-\uDDED\uDDF0-\uDDF3\uDDF7-\uDDF9\uDDFC\uDDFE])|\uD83C\uDDF3(?:\uD83C[\uDDE6\uDDE8\uDDEA-\uDDEC\uDDEE\uDDF1\uDDF4\uDDF5\uDDF7\uDDFA\uDDFF])|\uD83C\uDDF2(?:\uD83C[\uDDE6\uDDE8-\uDDED\uDDF0-\uDDFF])|\uD83C\uDDF1(?:\uD83C[\uDDE6-\uDDE8\uDDEE\uDDF0\uDDF7-\uDDFB\uDDFE])|\uD83C\uDDF0(?:\uD83C[\uDDEA\uDDEC-\uDDEE\uDDF2\uDDF3\uDDF5\uDDF7\uDDFC\uDDFE\uDDFF])|\uD83C\uDDEF(?:\uD83C[\uDDEA\uDDF2\uDDF4\uDDF5])|\uD83C\uDDEE(?:\uD83C[\uDDE8-\uDDEA\uDDF1-\uDDF4\uDDF6-\uDDF9])|\uD83C\uDDED(?:\uD83C[\uDDF0\uDDF2\uDDF3\uDDF7\uDDF9\uDDFA])|\uD83C\uDDEC(?:\uD83C[\uDDE6\uDDE7\uDDE9-\uDDEE\uDDF1-\uDDF3\uDDF5-\uDDFA\uDDFC\uDDFE])|\uD83C\uDDEB(?:\uD83C[\uDDEE-\uDDF0\uDDF2\uDDF4\uDDF7])|\uD83C\uDDEA(?:\uD83C[\uDDE6\uDDE8\uDDEA\uDDEC\uDDED\uDDF7-\uDDFA])|\uD83C\uDDE9(?:\uD83C[\uDDEA\uDDEC\uDDEF\uDDF0\uDDF2\uDDF4\uDDFF])|\uD83C\uDDE8(?:\uD83C[\uDDE6\uDDE8\uDDE9\uDDEB-\uDDEE\uDDF0-\uDDF5\uDDF7\uDDFA-\uDDFF])|\uD83C\uDDE7(?:\uD83C[\uDDE6\uDDE7\uDDE9-\uDDEF\uDDF1-\uDDF4\uDDF6-\uDDF9\uDDFB\uDDFC\uDDFE\uDDFF])|\uD83C\uDDE6(?:\uD83C[\uDDE8-\uDDEC\uDDEE\uDDF1\uDDF2\uDDF4\uDDF6-\uDDFA\uDDFC\uDDFD\uDDFF])|[#\*0-9]\uFE0F\u20E3|\u2764\uFE0F|(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD])(?:\uD83C[\uDFFB-\uDFFF])|(?:\u26F9|\uD83C[\uDFCB\uDFCC]|\uD83D\uDD75)(?:\uFE0F|\uD83C[\uDFFB-\uDFFF])|\uD83C\uDFF4|(?:[\u270A\u270B]|\uD83C[\uDF85\uDFC2\uDFC7]|\uD83D[\uDC42\uDC43\uDC46-\uDC50\uDC66\uDC67\uDC6B-\uDC6D\uDC72\uDC74-\uDC76\uDC78\uDC7C\uDC83\uDC85\uDC8F\uDC91\uDCAA\uDD7A\uDD95\uDD96\uDE4C\uDE4F\uDEC0\uDECC]|\uD83E[\uDD0C\uDD0F\uDD18-\uDD1C\uDD1E\uDD1F\uDD30-\uDD34\uDD36\uDD77\uDDB5\uDDB6\uDDBB\uDDD2\uDDD3\uDDD5])(?:\uD83C[\uDFFB-\uDFFF])|(?:[\u261D\u270C\u270D]|\uD83D[\uDD74\uDD90])(?:\uFE0F|\uD83C[\uDFFB-\uDFFF])|[\u270A\u270B]|\uD83C[\uDF85\uDFC2\uDFC7]|\uD83D[\uDC08\uDC15\uDC3B\uDC42\uDC43\uDC46-\uDC50\uDC66\uDC67\uDC6B-\uDC6D\uDC72\uDC74-\uDC76\uDC78\uDC7C\uDC83\uDC85\uDC8F\uDC91\uDCAA\uDD7A\uDD95\uDD96\uDE2E\uDE35\uDE36\uDE4C\uDE4F\uDEC0\uDECC]|\uD83E[\uDD0C\uDD0F\uDD18-\uDD1C\uDD1E\uDD1F\uDD30-\uDD34\uDD36\uDD77\uDDB5\uDDB6\uDDBB\uDDD2\uDDD3\uDDD5]|\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD]|\uD83D\uDC6F|\uD83E[\uDD3C\uDDDE\uDDDF]|[\u231A\u231B\u23E9-\u23EC\u23F0\u23F3\u25FD\u25FE\u2614\u2615\u2648-\u2653\u267F\u2693\u26A1\u26AA\u26AB\u26BD\u26BE\u26C4\u26C5\u26CE\u26D4\u26EA\u26F2\u26F3\u26F5\u26FA\u26FD\u2705\u2728\u274C\u274E\u2753-\u2755\u2757\u2795-\u2797\u27B0\u27BF\u2B1B\u2B1C\u2B50\u2B55]|\uD83C[\uDC04\uDCCF\uDD8E\uDD91-\uDD9A\uDE01\uDE1A\uDE2F\uDE32-\uDE36\uDE38-\uDE3A\uDE50\uDE51\uDF00-\uDF20\uDF2D-\uDF35\uDF37-\uDF7C\uDF7E-\uDF84\uDF86-\uDF93\uDFA0-\uDFC1\uDFC5\uDFC6\uDFC8\uDFC9\uDFCF-\uDFD3\uDFE0-\uDFF0\uDFF8-\uDFFF]|\uD83D[\uDC00-\uDC07\uDC09-\uDC14\uDC16-\uDC3A\uDC3C-\uDC3E\uDC40\uDC44\uDC45\uDC51-\uDC65\uDC6A\uDC79-\uDC7B\uDC7D-\uDC80\uDC84\uDC88-\uDC8E\uDC90\uDC92-\uDCA9\uDCAB-\uDCFC\uDCFF-\uDD3D\uDD4B-\uDD4E\uDD50-\uDD67\uDDA4\uDDFB-\uDE2D\uDE2F-\uDE34\uDE37-\uDE44\uDE48-\uDE4A\uDE80-\uDEA2\uDEA4-\uDEB3\uDEB7-\uDEBF\uDEC1-\uDEC5\uDED0-\uDED2\uDED5-\uDED7\uDEEB\uDEEC\uDEF4-\uDEFC\uDFE0-\uDFEB]|\uD83E[\uDD0D\uDD0E\uDD10-\uDD17\uDD1D\uDD20-\uDD25\uDD27-\uDD2F\uDD3A\uDD3F-\uDD45\uDD47-\uDD76\uDD78\uDD7A-\uDDB4\uDDB7\uDDBA\uDDBC-\uDDCB\uDDD0\uDDE0-\uDDFF\uDE70-\uDE74\uDE78-\uDE7A\uDE80-\uDE86\uDE90-\uDEA8\uDEB0-\uDEB6\uDEC0-\uDEC2\uDED0-\uDED6]|(?:[\u231A\u231B\u23E9-\u23EC\u23F0\u23F3\u25FD\u25FE\u2614\u2615\u2648-\u2653\u267F\u2693\u26A1\u26AA\u26AB\u26BD\u26BE\u26C4\u26C5\u26CE\u26D4\u26EA\u26F2\u26F3\u26F5\u26FA\u26FD\u2705\u270A\u270B\u2728\u274C\u274E\u2753-\u2755\u2757\u2795-\u2797\u27B0\u27BF\u2B1B\u2B1C\u2B50\u2B55]|\uD83C[\uDC04\uDCCF\uDD8E\uDD91-\uDD9A\uDDE6-\uDDFF\uDE01\uDE1A\uDE2F\uDE32-\uDE36\uDE38-\uDE3A\uDE50\uDE51\uDF00-\uDF20\uDF2D-\uDF35\uDF37-\uDF7C\uDF7E-\uDF93\uDFA0-\uDFCA\uDFCF-\uDFD3\uDFE0-\uDFF0\uDFF4\uDFF8-\uDFFF]|\uD83D[\uDC00-\uDC3E\uDC40\uDC42-\uDCFC\uDCFF-\uDD3D\uDD4B-\uDD4E\uDD50-\uDD67\uDD7A\uDD95\uDD96\uDDA4\uDDFB-\uDE4F\uDE80-\uDEC5\uDECC\uDED0-\uDED2\uDED5-\uDED7\uDEEB\uDEEC\uDEF4-\uDEFC\uDFE0-\uDFEB]|\uD83E[\uDD0C-\uDD3A\uDD3C-\uDD45\uDD47-\uDD78\uDD7A-\uDDCB\uDDCD-\uDDFF\uDE70-\uDE74\uDE78-\uDE7A\uDE80-\uDE86\uDE90-\uDEA8\uDEB0-\uDEB6\uDEC0-\uDEC2\uDED0-\uDED6])|(?:[#\*0-9\xA9\xAE\u203C\u2049\u2122\u2139\u2194-\u2199\u21A9\u21AA\u231A\u231B\u2328\u23CF\u23E9-\u23F3\u23F8-\u23FA\u24C2\u25AA\u25AB\u25B6\u25C0\u25FB-\u25FE\u2600-\u2604\u260E\u2611\u2614\u2615\u2618\u261D\u2620\u2622\u2623\u2626\u262A\u262E\u262F\u2638-\u263A\u2640\u2642\u2648-\u2653\u265F\u2660\u2663\u2665\u2666\u2668\u267B\u267E\u267F\u2692-\u2697\u2699\u269B\u269C\u26A0\u26A1\u26A7\u26AA\u26AB\u26B0\u26B1\u26BD\u26BE\u26C4\u26C5\u26C8\u26CE\u26CF\u26D1\u26D3\u26D4\u26E9\u26EA\u26F0-\u26F5\u26F7-\u26FA\u26FD\u2702\u2705\u2708-\u270D\u270F\u2712\u2714\u2716\u271D\u2721\u2728\u2733\u2734\u2744\u2747\u274C\u274E\u2753-\u2755\u2757\u2763\u2764\u2795-\u2797\u27A1\u27B0\u27BF\u2934\u2935\u2B05-\u2B07\u2B1B\u2B1C\u2B50\u2B55\u3030\u303D\u3297\u3299]|\uD83C[\uDC04\uDCCF\uDD70\uDD71\uDD7E\uDD7F\uDD8E\uDD91-\uDD9A\uDDE6-\uDDFF\uDE01\uDE02\uDE1A\uDE2F\uDE32-\uDE3A\uDE50\uDE51\uDF00-\uDF21\uDF24-\uDF93\uDF96\uDF97\uDF99-\uDF9B\uDF9E-\uDFF0\uDFF3-\uDFF5\uDFF7-\uDFFF]|\uD83D[\uDC00-\uDCFD\uDCFF-\uDD3D\uDD49-\uDD4E\uDD50-\uDD67\uDD6F\uDD70\uDD73-\uDD7A\uDD87\uDD8A-\uDD8D\uDD90\uDD95\uDD96\uDDA4\uDDA5\uDDA8\uDDB1\uDDB2\uDDBC\uDDC2-\uDDC4\uDDD1-\uDDD3\uDDDC-\uDDDE\uDDE1\uDDE3\uDDE8\uDDEF\uDDF3\uDDFA-\uDE4F\uDE80-\uDEC5\uDECB-\uDED2\uDED5-\uDED7\uDEE0-\uDEE5\uDEE9\uDEEB\uDEEC\uDEF0\uDEF3-\uDEFC\uDFE0-\uDFEB]|\uD83E[\uDD0C-\uDD3A\uDD3C-\uDD45\uDD47-\uDD78\uDD7A-\uDDCB\uDDCD-\uDDFF\uDE70-\uDE74\uDE78-\uDE7A\uDE80-\uDE86\uDE90-\uDEA8\uDEB0-\uDEB6\uDEC0-\uDEC2\uDED0-\uDED6])\uFE0F|(?:[\u261D\u26F9\u270A-\u270D]|\uD83C[\uDF85\uDFC2-\uDFC4\uDFC7\uDFCA-\uDFCC]|\uD83D[\uDC42\uDC43\uDC46-\uDC50\uDC66-\uDC78\uDC7C\uDC81-\uDC83\uDC85-\uDC87\uDC8F\uDC91\uDCAA\uDD74\uDD75\uDD7A\uDD90\uDD95\uDD96\uDE45-\uDE47\uDE4B-\uDE4F\uDEA3\uDEB4-\uDEB6\uDEC0\uDECC]|\uD83E[\uDD0C\uDD0F\uDD18-\uDD1F\uDD26\uDD30-\uDD39\uDD3C-\uDD3E\uDD77\uDDB5\uDDB6\uDDB8\uDDB9\uDDBB\uDDCD-\uDDCF\uDDD1-\uDDDD])/g;
      };
    }
  });

  // ../../../.yarn/cache/cli-boxes-npm-3.0.0-e5de3a0d5e-637d84419d.zip/node_modules/cli-boxes/boxes.json
  var require_boxes = __commonJS({
    "../../../.yarn/cache/cli-boxes-npm-3.0.0-e5de3a0d5e-637d84419d.zip/node_modules/cli-boxes/boxes.json"(exports2, module2) {
      module2.exports = {
        single: {
          topLeft: "\u250C",
          top: "\u2500",
          topRight: "\u2510",
          right: "\u2502",
          bottomRight: "\u2518",
          bottom: "\u2500",
          bottomLeft: "\u2514",
          left: "\u2502"
        },
        double: {
          topLeft: "\u2554",
          top: "\u2550",
          topRight: "\u2557",
          right: "\u2551",
          bottomRight: "\u255D",
          bottom: "\u2550",
          bottomLeft: "\u255A",
          left: "\u2551"
        },
        round: {
          topLeft: "\u256D",
          top: "\u2500",
          topRight: "\u256E",
          right: "\u2502",
          bottomRight: "\u256F",
          bottom: "\u2500",
          bottomLeft: "\u2570",
          left: "\u2502"
        },
        bold: {
          topLeft: "\u250F",
          top: "\u2501",
          topRight: "\u2513",
          right: "\u2503",
          bottomRight: "\u251B",
          bottom: "\u2501",
          bottomLeft: "\u2517",
          left: "\u2503"
        },
        singleDouble: {
          topLeft: "\u2553",
          top: "\u2500",
          topRight: "\u2556",
          right: "\u2551",
          bottomRight: "\u255C",
          bottom: "\u2500",
          bottomLeft: "\u2559",
          left: "\u2551"
        },
        doubleSingle: {
          topLeft: "\u2552",
          top: "\u2550",
          topRight: "\u2555",
          right: "\u2502",
          bottomRight: "\u255B",
          bottom: "\u2550",
          bottomLeft: "\u2558",
          left: "\u2502"
        },
        classic: {
          topLeft: "+",
          top: "-",
          topRight: "+",
          right: "|",
          bottomRight: "+",
          bottom: "-",
          bottomLeft: "+",
          left: "|"
        },
        arrow: {
          topLeft: "\u2198",
          top: "\u2193",
          topRight: "\u2199",
          right: "\u2190",
          bottomRight: "\u2196",
          bottom: "\u2191",
          bottomLeft: "\u2197",
          left: "\u2192"
        }
      };
    }
  });

  // ../../../.yarn/cache/cli-boxes-npm-3.0.0-e5de3a0d5e-637d84419d.zip/node_modules/cli-boxes/index.js
  var require_cli_boxes = __commonJS({
    "../../../.yarn/cache/cli-boxes-npm-3.0.0-e5de3a0d5e-637d84419d.zip/node_modules/cli-boxes/index.js"(exports2, module2) {
      "use strict";
      var cliBoxes2 = require_boxes();
      module2.exports = cliBoxes2;
      module2.exports.default = cliBoxes2;
    }
  });

  // ../../../.yarn/cache/ansi-regex-npm-5.0.1-c963a48615-2aa4bb54ca.zip/node_modules/ansi-regex/index.js
  var require_ansi_regex = __commonJS({
    "../../../.yarn/cache/ansi-regex-npm-5.0.1-c963a48615-2aa4bb54ca.zip/node_modules/ansi-regex/index.js"(exports2, module2) {
      "use strict";
      module2.exports = ({ onlyFirst = false } = {}) => {
        const pattern = [
          "[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]+)*|[a-zA-Z\\d]+(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]*)*)?\\u0007)",
          "(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-ntqry=><~]))"
        ].join("|");
        return new RegExp(pattern, onlyFirst ? void 0 : "g");
      };
    }
  });

  // ../../../.yarn/cache/strip-ansi-npm-6.0.1-caddc7cb40-ae3b5436d3.zip/node_modules/strip-ansi/index.js
  var require_strip_ansi = __commonJS({
    "../../../.yarn/cache/strip-ansi-npm-6.0.1-caddc7cb40-ae3b5436d3.zip/node_modules/strip-ansi/index.js"(exports2, module2) {
      "use strict";
      var ansiRegex2 = require_ansi_regex();
      module2.exports = (string) => typeof string === "string" ? string.replace(ansiRegex2(), "") : string;
    }
  });

  // ../../../.yarn/cache/is-fullwidth-code-point-npm-3.0.0-1ecf4ebee5-44a30c2945.zip/node_modules/is-fullwidth-code-point/index.js
  var require_is_fullwidth_code_point = __commonJS({
    "../../../.yarn/cache/is-fullwidth-code-point-npm-3.0.0-1ecf4ebee5-44a30c2945.zip/node_modules/is-fullwidth-code-point/index.js"(exports2, module2) {
      "use strict";
      var isFullwidthCodePoint = (codePoint) => {
        if (Number.isNaN(codePoint)) {
          return false;
        }
        if (codePoint >= 4352 && (codePoint <= 4447 || codePoint === 9001 || codePoint === 9002 || 11904 <= codePoint && codePoint <= 12871 && codePoint !== 12351 || 12880 <= codePoint && codePoint <= 19903 || 19968 <= codePoint && codePoint <= 42182 || 43360 <= codePoint && codePoint <= 43388 || 44032 <= codePoint && codePoint <= 55203 || 63744 <= codePoint && codePoint <= 64255 || 65040 <= codePoint && codePoint <= 65049 || 65072 <= codePoint && codePoint <= 65131 || 65281 <= codePoint && codePoint <= 65376 || 65504 <= codePoint && codePoint <= 65510 || 110592 <= codePoint && codePoint <= 110593 || 127488 <= codePoint && codePoint <= 127569 || 131072 <= codePoint && codePoint <= 262141)) {
          return true;
        }
        return false;
      };
      module2.exports = isFullwidthCodePoint;
      module2.exports.default = isFullwidthCodePoint;
    }
  });

  // ../../../.yarn/cache/emoji-regex-npm-8.0.0-213764015c-c72d67a682.zip/node_modules/emoji-regex/index.js
  var require_emoji_regex2 = __commonJS({
    "../../../.yarn/cache/emoji-regex-npm-8.0.0-213764015c-c72d67a682.zip/node_modules/emoji-regex/index.js"(exports2, module2) {
      "use strict";
      module2.exports = function() {
        return /\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62(?:\uDB40\uDC65\uDB40\uDC6E\uDB40\uDC67|\uDB40\uDC73\uDB40\uDC63\uDB40\uDC74|\uDB40\uDC77\uDB40\uDC6C\uDB40\uDC73)\uDB40\uDC7F|\uD83D\uDC68(?:\uD83C\uDFFC\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68\uD83C\uDFFB|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFE])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFE\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFD])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB\uDFFC])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83D\uDC68|(?:\uD83D[\uDC68\uDC69])\u200D(?:\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67]))|\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67])|(?:\uD83D[\uDC68\uDC69])\u200D(?:\uD83D[\uDC66\uDC67])|[\u2695\u2696\u2708]\uFE0F|\uD83D[\uDC66\uDC67]|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|(?:\uD83C\uDFFB\u200D[\u2695\u2696\u2708]|\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708])\uFE0F|\uD83C\uDFFB\u200D(?:\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C[\uDFFB-\uDFFF])|(?:\uD83E\uDDD1\uD83C\uDFFB\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFC\u200D\uD83E\uDD1D\u200D\uD83D\uDC69)\uD83C\uDFFB|\uD83E\uDDD1(?:\uD83C\uDFFF\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1(?:\uD83C[\uDFFB-\uDFFF])|\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1)|(?:\uD83E\uDDD1\uD83C\uDFFE\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFF\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB-\uDFFE])|(?:\uD83E\uDDD1\uD83C\uDFFC\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFD\u200D\uD83E\uDD1D\u200D\uD83D\uDC69)(?:\uD83C[\uDFFB\uDFFC])|\uD83D\uDC69(?:\uD83C\uDFFE\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFD\uDFFF])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFC\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB\uDFFD-\uDFFF])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFB\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFC-\uDFFF])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB\uDFFC\uDFFE\uDFFF])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D(?:\uD83D[\uDC68\uDC69])|\uD83D[\uDC68\uDC69])|\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83C[\uDF3E\uDF73\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD]))|\uD83D\uDC69\u200D\uD83D\uDC69\u200D(?:\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67]))|(?:\uD83E\uDDD1\uD83C\uDFFD\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFE\u200D\uD83E\uDD1D\u200D\uD83D\uDC69)(?:\uD83C[\uDFFB-\uDFFD])|\uD83D\uDC69\u200D\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC69\u200D\uD83D\uDC69\u200D(?:\uD83D[\uDC66\uDC67])|(?:\uD83D\uDC41\uFE0F\u200D\uD83D\uDDE8|\uD83D\uDC69(?:\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708]|\uD83C\uDFFB\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\u200D[\u2695\u2696\u2708])|(?:(?:\u26F9|\uD83C[\uDFCB\uDFCC]|\uD83D\uDD75)\uFE0F|\uD83D\uDC6F|\uD83E[\uDD3C\uDDDE\uDDDF])\u200D[\u2640\u2642]|(?:\u26F9|\uD83C[\uDFCB\uDFCC]|\uD83D\uDD75)(?:\uD83C[\uDFFB-\uDFFF])\u200D[\u2640\u2642]|(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD6-\uDDDD])(?:(?:\uD83C[\uDFFB-\uDFFF])\u200D[\u2640\u2642]|\u200D[\u2640\u2642])|\uD83C\uDFF4\u200D\u2620)\uFE0F|\uD83D\uDC69\u200D\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67])|\uD83C\uDFF3\uFE0F\u200D\uD83C\uDF08|\uD83D\uDC15\u200D\uD83E\uDDBA|\uD83D\uDC69\u200D\uD83D\uDC66|\uD83D\uDC69\u200D\uD83D\uDC67|\uD83C\uDDFD\uD83C\uDDF0|\uD83C\uDDF4\uD83C\uDDF2|\uD83C\uDDF6\uD83C\uDDE6|[#\*0-9]\uFE0F\u20E3|\uD83C\uDDE7(?:\uD83C[\uDDE6\uDDE7\uDDE9-\uDDEF\uDDF1-\uDDF4\uDDF6-\uDDF9\uDDFB\uDDFC\uDDFE\uDDFF])|\uD83C\uDDF9(?:\uD83C[\uDDE6\uDDE8\uDDE9\uDDEB-\uDDED\uDDEF-\uDDF4\uDDF7\uDDF9\uDDFB\uDDFC\uDDFF])|\uD83C\uDDEA(?:\uD83C[\uDDE6\uDDE8\uDDEA\uDDEC\uDDED\uDDF7-\uDDFA])|\uD83E\uDDD1(?:\uD83C[\uDFFB-\uDFFF])|\uD83C\uDDF7(?:\uD83C[\uDDEA\uDDF4\uDDF8\uDDFA\uDDFC])|\uD83D\uDC69(?:\uD83C[\uDFFB-\uDFFF])|\uD83C\uDDF2(?:\uD83C[\uDDE6\uDDE8-\uDDED\uDDF0-\uDDFF])|\uD83C\uDDE6(?:\uD83C[\uDDE8-\uDDEC\uDDEE\uDDF1\uDDF2\uDDF4\uDDF6-\uDDFA\uDDFC\uDDFD\uDDFF])|\uD83C\uDDF0(?:\uD83C[\uDDEA\uDDEC-\uDDEE\uDDF2\uDDF3\uDDF5\uDDF7\uDDFC\uDDFE\uDDFF])|\uD83C\uDDED(?:\uD83C[\uDDF0\uDDF2\uDDF3\uDDF7\uDDF9\uDDFA])|\uD83C\uDDE9(?:\uD83C[\uDDEA\uDDEC\uDDEF\uDDF0\uDDF2\uDDF4\uDDFF])|\uD83C\uDDFE(?:\uD83C[\uDDEA\uDDF9])|\uD83C\uDDEC(?:\uD83C[\uDDE6\uDDE7\uDDE9-\uDDEE\uDDF1-\uDDF3\uDDF5-\uDDFA\uDDFC\uDDFE])|\uD83C\uDDF8(?:\uD83C[\uDDE6-\uDDEA\uDDEC-\uDDF4\uDDF7-\uDDF9\uDDFB\uDDFD-\uDDFF])|\uD83C\uDDEB(?:\uD83C[\uDDEE-\uDDF0\uDDF2\uDDF4\uDDF7])|\uD83C\uDDF5(?:\uD83C[\uDDE6\uDDEA-\uDDED\uDDF0-\uDDF3\uDDF7-\uDDF9\uDDFC\uDDFE])|\uD83C\uDDFB(?:\uD83C[\uDDE6\uDDE8\uDDEA\uDDEC\uDDEE\uDDF3\uDDFA])|\uD83C\uDDF3(?:\uD83C[\uDDE6\uDDE8\uDDEA-\uDDEC\uDDEE\uDDF1\uDDF4\uDDF5\uDDF7\uDDFA\uDDFF])|\uD83C\uDDE8(?:\uD83C[\uDDE6\uDDE8\uDDE9\uDDEB-\uDDEE\uDDF0-\uDDF5\uDDF7\uDDFA-\uDDFF])|\uD83C\uDDF1(?:\uD83C[\uDDE6-\uDDE8\uDDEE\uDDF0\uDDF7-\uDDFB\uDDFE])|\uD83C\uDDFF(?:\uD83C[\uDDE6\uDDF2\uDDFC])|\uD83C\uDDFC(?:\uD83C[\uDDEB\uDDF8])|\uD83C\uDDFA(?:\uD83C[\uDDE6\uDDEC\uDDF2\uDDF3\uDDF8\uDDFE\uDDFF])|\uD83C\uDDEE(?:\uD83C[\uDDE8-\uDDEA\uDDF1-\uDDF4\uDDF6-\uDDF9])|\uD83C\uDDEF(?:\uD83C[\uDDEA\uDDF2\uDDF4\uDDF5])|(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD6-\uDDDD])(?:\uD83C[\uDFFB-\uDFFF])|(?:\u26F9|\uD83C[\uDFCB\uDFCC]|\uD83D\uDD75)(?:\uD83C[\uDFFB-\uDFFF])|(?:[\u261D\u270A-\u270D]|\uD83C[\uDF85\uDFC2\uDFC7]|\uD83D[\uDC42\uDC43\uDC46-\uDC50\uDC66\uDC67\uDC6B-\uDC6D\uDC70\uDC72\uDC74-\uDC76\uDC78\uDC7C\uDC83\uDC85\uDCAA\uDD74\uDD7A\uDD90\uDD95\uDD96\uDE4C\uDE4F\uDEC0\uDECC]|\uD83E[\uDD0F\uDD18-\uDD1C\uDD1E\uDD1F\uDD30-\uDD36\uDDB5\uDDB6\uDDBB\uDDD2-\uDDD5])(?:\uD83C[\uDFFB-\uDFFF])|(?:[\u231A\u231B\u23E9-\u23EC\u23F0\u23F3\u25FD\u25FE\u2614\u2615\u2648-\u2653\u267F\u2693\u26A1\u26AA\u26AB\u26BD\u26BE\u26C4\u26C5\u26CE\u26D4\u26EA\u26F2\u26F3\u26F5\u26FA\u26FD\u2705\u270A\u270B\u2728\u274C\u274E\u2753-\u2755\u2757\u2795-\u2797\u27B0\u27BF\u2B1B\u2B1C\u2B50\u2B55]|\uD83C[\uDC04\uDCCF\uDD8E\uDD91-\uDD9A\uDDE6-\uDDFF\uDE01\uDE1A\uDE2F\uDE32-\uDE36\uDE38-\uDE3A\uDE50\uDE51\uDF00-\uDF20\uDF2D-\uDF35\uDF37-\uDF7C\uDF7E-\uDF93\uDFA0-\uDFCA\uDFCF-\uDFD3\uDFE0-\uDFF0\uDFF4\uDFF8-\uDFFF]|\uD83D[\uDC00-\uDC3E\uDC40\uDC42-\uDCFC\uDCFF-\uDD3D\uDD4B-\uDD4E\uDD50-\uDD67\uDD7A\uDD95\uDD96\uDDA4\uDDFB-\uDE4F\uDE80-\uDEC5\uDECC\uDED0-\uDED2\uDED5\uDEEB\uDEEC\uDEF4-\uDEFA\uDFE0-\uDFEB]|\uD83E[\uDD0D-\uDD3A\uDD3C-\uDD45\uDD47-\uDD71\uDD73-\uDD76\uDD7A-\uDDA2\uDDA5-\uDDAA\uDDAE-\uDDCA\uDDCD-\uDDFF\uDE70-\uDE73\uDE78-\uDE7A\uDE80-\uDE82\uDE90-\uDE95])|(?:[#\*0-9\xA9\xAE\u203C\u2049\u2122\u2139\u2194-\u2199\u21A9\u21AA\u231A\u231B\u2328\u23CF\u23E9-\u23F3\u23F8-\u23FA\u24C2\u25AA\u25AB\u25B6\u25C0\u25FB-\u25FE\u2600-\u2604\u260E\u2611\u2614\u2615\u2618\u261D\u2620\u2622\u2623\u2626\u262A\u262E\u262F\u2638-\u263A\u2640\u2642\u2648-\u2653\u265F\u2660\u2663\u2665\u2666\u2668\u267B\u267E\u267F\u2692-\u2697\u2699\u269B\u269C\u26A0\u26A1\u26AA\u26AB\u26B0\u26B1\u26BD\u26BE\u26C4\u26C5\u26C8\u26CE\u26CF\u26D1\u26D3\u26D4\u26E9\u26EA\u26F0-\u26F5\u26F7-\u26FA\u26FD\u2702\u2705\u2708-\u270D\u270F\u2712\u2714\u2716\u271D\u2721\u2728\u2733\u2734\u2744\u2747\u274C\u274E\u2753-\u2755\u2757\u2763\u2764\u2795-\u2797\u27A1\u27B0\u27BF\u2934\u2935\u2B05-\u2B07\u2B1B\u2B1C\u2B50\u2B55\u3030\u303D\u3297\u3299]|\uD83C[\uDC04\uDCCF\uDD70\uDD71\uDD7E\uDD7F\uDD8E\uDD91-\uDD9A\uDDE6-\uDDFF\uDE01\uDE02\uDE1A\uDE2F\uDE32-\uDE3A\uDE50\uDE51\uDF00-\uDF21\uDF24-\uDF93\uDF96\uDF97\uDF99-\uDF9B\uDF9E-\uDFF0\uDFF3-\uDFF5\uDFF7-\uDFFF]|\uD83D[\uDC00-\uDCFD\uDCFF-\uDD3D\uDD49-\uDD4E\uDD50-\uDD67\uDD6F\uDD70\uDD73-\uDD7A\uDD87\uDD8A-\uDD8D\uDD90\uDD95\uDD96\uDDA4\uDDA5\uDDA8\uDDB1\uDDB2\uDDBC\uDDC2-\uDDC4\uDDD1-\uDDD3\uDDDC-\uDDDE\uDDE1\uDDE3\uDDE8\uDDEF\uDDF3\uDDFA-\uDE4F\uDE80-\uDEC5\uDECB-\uDED2\uDED5\uDEE0-\uDEE5\uDEE9\uDEEB\uDEEC\uDEF0\uDEF3-\uDEFA\uDFE0-\uDFEB]|\uD83E[\uDD0D-\uDD3A\uDD3C-\uDD45\uDD47-\uDD71\uDD73-\uDD76\uDD7A-\uDDA2\uDDA5-\uDDAA\uDDAE-\uDDCA\uDDCD-\uDDFF\uDE70-\uDE73\uDE78-\uDE7A\uDE80-\uDE82\uDE90-\uDE95])\uFE0F|(?:[\u261D\u26F9\u270A-\u270D]|\uD83C[\uDF85\uDFC2-\uDFC4\uDFC7\uDFCA-\uDFCC]|\uD83D[\uDC42\uDC43\uDC46-\uDC50\uDC66-\uDC78\uDC7C\uDC81-\uDC83\uDC85-\uDC87\uDC8F\uDC91\uDCAA\uDD74\uDD75\uDD7A\uDD90\uDD95\uDD96\uDE45-\uDE47\uDE4B-\uDE4F\uDEA3\uDEB4-\uDEB6\uDEC0\uDECC]|\uD83E[\uDD0F\uDD18-\uDD1F\uDD26\uDD30-\uDD39\uDD3C-\uDD3E\uDDB5\uDDB6\uDDB8\uDDB9\uDDBB\uDDCD-\uDDCF\uDDD1-\uDDDD])/g;
      };
    }
  });

  // ../../../.yarn/cache/string-width-npm-4.2.3-2c27177bae-e52c10dc3f.zip/node_modules/string-width/index.js
  var require_string_width = __commonJS({
    "../../../.yarn/cache/string-width-npm-4.2.3-2c27177bae-e52c10dc3f.zip/node_modules/string-width/index.js"(exports2, module2) {
      "use strict";
      var stripAnsi2 = require_strip_ansi();
      var isFullwidthCodePoint = require_is_fullwidth_code_point();
      var emojiRegex2 = require_emoji_regex2();
      var stringWidth2 = (string) => {
        if (typeof string !== "string" || string.length === 0) {
          return 0;
        }
        string = stripAnsi2(string);
        if (string.length === 0) {
          return 0;
        }
        string = string.replace(emojiRegex2(), "  ");
        let width = 0;
        for (let i = 0; i < string.length; i++) {
          const code = string.codePointAt(i);
          if (code <= 31 || code >= 127 && code <= 159) {
            continue;
          }
          if (code >= 768 && code <= 879) {
            continue;
          }
          if (code > 65535) {
            i++;
          }
          width += isFullwidthCodePoint(code) ? 2 : 1;
        }
        return width;
      };
      module2.exports = stringWidth2;
      module2.exports.default = stringWidth2;
    }
  });

  // ../../../.yarn/cache/ansi-align-npm-3.0.1-8e6288d20a-4c7e8b6a10.zip/node_modules/ansi-align/index.js
  var require_ansi_align = __commonJS({
    "../../../.yarn/cache/ansi-align-npm-3.0.1-8e6288d20a-4c7e8b6a10.zip/node_modules/ansi-align/index.js"(exports2, module2) {
      "use strict";
      var stringWidth2 = require_string_width();
      function ansiAlign2(text, opts) {
        if (!text)
          return text;
        opts = opts || {};
        const align = opts.align || "center";
        if (align === "left")
          return text;
        const split = opts.split || "\n";
        const pad = opts.pad || " ";
        const widthDiffFn = align !== "right" ? halfDiff : fullDiff;
        let returnString = false;
        if (!Array.isArray(text)) {
          returnString = true;
          text = String(text).split(split);
        }
        let width;
        let maxWidth = 0;
        text = text.map(function(str) {
          str = String(str);
          width = stringWidth2(str);
          maxWidth = Math.max(width, maxWidth);
          return {
            str,
            width
          };
        }).map(function(obj) {
          return new Array(widthDiffFn(maxWidth, obj.width) + 1).join(pad) + obj.str;
        });
        return returnString ? text.join(split) : text;
      }
      ansiAlign2.left = function left(text) {
        return ansiAlign2(text, { align: "left" });
      };
      ansiAlign2.center = function center(text) {
        return ansiAlign2(text, { align: "center" });
      };
      ansiAlign2.right = function right(text) {
        return ansiAlign2(text, { align: "right" });
      };
      module2.exports = ansiAlign2;
      function halfDiff(maxWidth, curWidth) {
        return Math.floor((maxWidth - curWidth) / 2);
      }
      function fullDiff(maxWidth, curWidth) {
        return maxWidth - curWidth;
      }
    }
  });

  // ../../../.yarn/cache/yocto-queue-npm-0.1.0-c6c9a7db29-f77b3d8d00.zip/node_modules/yocto-queue/index.js
  var require_yocto_queue = __commonJS({
    "../../../.yarn/cache/yocto-queue-npm-0.1.0-c6c9a7db29-f77b3d8d00.zip/node_modules/yocto-queue/index.js"(exports2, module2) {
      var Node = class {
        constructor(value) {
          this.value = value;
          this.next = void 0;
        }
      };
      var Queue = class {
        constructor() {
          this.clear();
        }
        enqueue(value) {
          const node = new Node(value);
          if (this._head) {
            this._tail.next = node;
            this._tail = node;
          } else {
            this._head = node;
            this._tail = node;
          }
          this._size++;
        }
        dequeue() {
          const current = this._head;
          if (!current) {
            return;
          }
          this._head = this._head.next;
          this._size--;
          return current.value;
        }
        clear() {
          this._head = void 0;
          this._tail = void 0;
          this._size = 0;
        }
        get size() {
          return this._size;
        }
        *[Symbol.iterator]() {
          let current = this._head;
          while (current) {
            yield current.value;
            current = current.next;
          }
        }
      };
      module2.exports = Queue;
    }
  });

  // ../../../.yarn/cache/p-limit-npm-3.1.0-05d2ede37f-7c3690c4db.zip/node_modules/p-limit/index.js
  var require_p_limit = __commonJS({
    "../../../.yarn/cache/p-limit-npm-3.1.0-05d2ede37f-7c3690c4db.zip/node_modules/p-limit/index.js"(exports2, module2) {
      "use strict";
      var Queue = require_yocto_queue();
      var pLimit = (concurrency) => {
        if (!((Number.isInteger(concurrency) || concurrency === Infinity) && concurrency > 0)) {
          throw new TypeError("Expected `concurrency` to be a number from 1 and up");
        }
        const queue = new Queue();
        let activeCount = 0;
        const next = () => {
          activeCount--;
          if (queue.size > 0) {
            queue.dequeue()();
          }
        };
        const run = async (fn, resolve2, ...args) => {
          activeCount++;
          const result = (async () => fn(...args))();
          resolve2(result);
          try {
            await result;
          } catch {
          }
          next();
        };
        const enqueue = (fn, resolve2, ...args) => {
          queue.enqueue(run.bind(null, fn, resolve2, ...args));
          (async () => {
            await Promise.resolve();
            if (activeCount < concurrency && queue.size > 0) {
              queue.dequeue()();
            }
          })();
        };
        const generator = (fn, ...args) => new Promise((resolve2) => {
          enqueue(fn, resolve2, ...args);
        });
        Object.defineProperties(generator, {
          activeCount: {
            get: () => activeCount
          },
          pendingCount: {
            get: () => queue.size
          },
          clearQueue: {
            value: () => {
              queue.clear();
            }
          }
        });
        return generator;
      };
      module2.exports = pLimit;
    }
  });

  // ../../../.yarn/cache/p-locate-npm-5.0.0-92cc7c7a3e-1623088f36.zip/node_modules/p-locate/index.js
  var require_p_locate = __commonJS({
    "../../../.yarn/cache/p-locate-npm-5.0.0-92cc7c7a3e-1623088f36.zip/node_modules/p-locate/index.js"(exports2, module2) {
      "use strict";
      var pLimit = require_p_limit();
      var EndError = class extends Error {
        constructor(value) {
          super();
          this.value = value;
        }
      };
      var testElement = async (element, tester) => tester(await element);
      var finder = async (element) => {
        const values = await Promise.all(element);
        if (values[1] === true) {
          throw new EndError(values[0]);
        }
        return false;
      };
      var pLocate = async (iterable, tester, options) => {
        options = {
          concurrency: Infinity,
          preserveOrder: true,
          ...options
        };
        const limit = pLimit(options.concurrency);
        const items = [...iterable].map((element) => [element, limit(testElement, element, tester)]);
        const checkLimit = pLimit(options.preserveOrder ? 1 : Infinity);
        try {
          await Promise.all(items.map((element) => checkLimit(finder, element)));
        } catch (error) {
          if (error instanceof EndError) {
            return error.value;
          }
          throw error;
        }
      };
      module2.exports = pLocate;
    }
  });

  // ../../../.yarn/cache/locate-path-npm-6.0.0-06a1e4c528-72eb661788.zip/node_modules/locate-path/index.js
  var require_locate_path = __commonJS({
    "../../../.yarn/cache/locate-path-npm-6.0.0-06a1e4c528-72eb661788.zip/node_modules/locate-path/index.js"(exports2, module2) {
      "use strict";
      var path2 = __require("path");
      var fs2 = __require("fs");
      var { promisify } = __require("util");
      var pLocate = require_p_locate();
      var fsStat = promisify(fs2.stat);
      var fsLStat = promisify(fs2.lstat);
      var typeMappings = {
        directory: "isDirectory",
        file: "isFile"
      };
      function checkType({ type }) {
        if (type in typeMappings) {
          return;
        }
        throw new Error(`Invalid type specified: ${type}`);
      }
      var matchType = (type, stat) => type === void 0 || stat[typeMappings[type]]();
      module2.exports = async (paths, options) => {
        options = {
          cwd: process.cwd(),
          type: "file",
          allowSymlinks: true,
          ...options
        };
        checkType(options);
        const statFn = options.allowSymlinks ? fsStat : fsLStat;
        return pLocate(paths, async (path_) => {
          try {
            const stat = await statFn(path2.resolve(options.cwd, path_));
            return matchType(options.type, stat);
          } catch {
            return false;
          }
        }, options);
      };
      module2.exports.sync = (paths, options) => {
        options = {
          cwd: process.cwd(),
          allowSymlinks: true,
          type: "file",
          ...options
        };
        checkType(options);
        const statFn = options.allowSymlinks ? fs2.statSync : fs2.lstatSync;
        for (const path_ of paths) {
          try {
            const stat = statFn(path2.resolve(options.cwd, path_));
            if (matchType(options.type, stat)) {
              return path_;
            }
          } catch {
          }
        }
      };
    }
  });

  // ../../../.yarn/cache/path-exists-npm-4.0.0-e9e4f63eb0-505807199d.zip/node_modules/path-exists/index.js
  var require_path_exists = __commonJS({
    "../../../.yarn/cache/path-exists-npm-4.0.0-e9e4f63eb0-505807199d.zip/node_modules/path-exists/index.js"(exports2, module2) {
      "use strict";
      var fs2 = __require("fs");
      var { promisify } = __require("util");
      var pAccess = promisify(fs2.access);
      module2.exports = async (path2) => {
        try {
          await pAccess(path2);
          return true;
        } catch (_) {
          return false;
        }
      };
      module2.exports.sync = (path2) => {
        try {
          fs2.accessSync(path2);
          return true;
        } catch (_) {
          return false;
        }
      };
    }
  });

  // ../../../.yarn/unplugged/find-up-npm-5.0.0-e03e9b796d/node_modules/find-up/index.js
  var require_find_up = __commonJS({
    "../../../.yarn/unplugged/find-up-npm-5.0.0-e03e9b796d/node_modules/find-up/index.js"(exports2, module2) {
      "use strict";
      var path2 = __require("path");
      var locatePath = require_locate_path();
      var pathExists = require_path_exists();
      var stop = Symbol("findUp.stop");
      module2.exports = async (name, options = {}) => {
        let directory = path2.resolve(options.cwd || "");
        const { root } = path2.parse(directory);
        const paths = [].concat(name);
        const runMatcher = async (locateOptions) => {
          if (typeof name !== "function") {
            return locatePath(paths, locateOptions);
          }
          const foundPath = await name(locateOptions.cwd);
          if (typeof foundPath === "string") {
            return locatePath([foundPath], locateOptions);
          }
          return foundPath;
        };
        while (true) {
          const foundPath = await runMatcher({ ...options, cwd: directory });
          if (foundPath === stop) {
            return;
          }
          if (foundPath) {
            return path2.resolve(directory, foundPath);
          }
          if (directory === root) {
            return;
          }
          directory = path2.dirname(directory);
        }
      };
      module2.exports.sync = (name, options = {}) => {
        let directory = path2.resolve(options.cwd || "");
        const { root } = path2.parse(directory);
        const paths = [].concat(name);
        const runMatcher = (locateOptions) => {
          if (typeof name !== "function") {
            return locatePath.sync(paths, locateOptions);
          }
          const foundPath = name(locateOptions.cwd);
          if (typeof foundPath === "string") {
            return locatePath.sync([foundPath], locateOptions);
          }
          return foundPath;
        };
        while (true) {
          const foundPath = runMatcher({ ...options, cwd: directory });
          if (foundPath === stop) {
            return;
          }
          if (foundPath) {
            return path2.resolve(directory, foundPath);
          }
          if (directory === root) {
            return;
          }
          directory = path2.dirname(directory);
        }
      };
      module2.exports.exists = pathExists;
      module2.exports.sync.exists = pathExists.sync;
      module2.exports.stop = stop;
    }
  });

  // sources/index.ts
  var sources_exports = {};
  __export(sources_exports, {
    default: () => sources_default
  });
  var console = __toESM(__require("console"));
  var fs = __toESM(__require("fs"));
  var path = __toESM(__require("path"));
  var process4 = __toESM(__require("process"));
  var import_toml = __toESM(require_toml());
  var import_core = __require("@yarnpkg/core");

  // ../../../.yarn/cache/boxen-npm-7.1.1-e79a50b11c-a21d514435.zip/node_modules/boxen/index.js
  var import_node_process2 = __toESM(__require("process"), 1);

  // ../../../.yarn/cache/ansi-regex-npm-6.0.1-8d663a607d-1ff8b7667c.zip/node_modules/ansi-regex/index.js
  function ansiRegex({ onlyFirst = false } = {}) {
    const pattern = [
      "[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]+)*|[a-zA-Z\\d]+(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]*)*)?\\u0007)",
      "(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-ntqry=><~]))"
    ].join("|");
    return new RegExp(pattern, onlyFirst ? void 0 : "g");
  }

  // ../../../.yarn/cache/strip-ansi-npm-7.1.0-7453b80b79-475f53e9c4.zip/node_modules/strip-ansi/index.js
  var regex = ansiRegex();
  function stripAnsi(string) {
    if (typeof string !== "string") {
      throw new TypeError(`Expected a \`string\`, got \`${typeof string}\``);
    }
    return string.replace(regex, "");
  }

  // ../../../.yarn/cache/string-width-npm-5.1.2-bf60531341-7369deaa29.zip/node_modules/string-width/index.js
  var import_eastasianwidth = __toESM(require_eastasianwidth(), 1);
  var import_emoji_regex = __toESM(require_emoji_regex(), 1);
  function stringWidth(string, options = {}) {
    if (typeof string !== "string" || string.length === 0) {
      return 0;
    }
    options = {
      ambiguousIsNarrow: true,
      ...options
    };
    string = stripAnsi(string);
    if (string.length === 0) {
      return 0;
    }
    string = string.replace((0, import_emoji_regex.default)(), "  ");
    const ambiguousCharacterWidth = options.ambiguousIsNarrow ? 1 : 2;
    let width = 0;
    for (const character of string) {
      const codePoint = character.codePointAt(0);
      if (codePoint <= 31 || codePoint >= 127 && codePoint <= 159) {
        continue;
      }
      if (codePoint >= 768 && codePoint <= 879) {
        continue;
      }
      const code = import_eastasianwidth.default.eastAsianWidth(character);
      switch (code) {
        case "F":
        case "W":
          width += 2;
          break;
        case "A":
          width += ambiguousCharacterWidth;
          break;
        default:
          width += 1;
      }
    }
    return width;
  }

  // ../../../.yarn/cache/chalk-npm-5.3.0-d181999efb-6373caaab2.zip/node_modules/chalk/source/vendor/ansi-styles/index.js
  var ANSI_BACKGROUND_OFFSET = 10;
  var wrapAnsi16 = (offset = 0) => (code) => `\x1B[${code + offset}m`;
  var wrapAnsi256 = (offset = 0) => (code) => `\x1B[${38 + offset};5;${code}m`;
  var wrapAnsi16m = (offset = 0) => (red, green, blue) => `\x1B[${38 + offset};2;${red};${green};${blue}m`;
  var styles = {
    modifier: {
      reset: [0, 0],
      bold: [1, 22],
      dim: [2, 22],
      italic: [3, 23],
      underline: [4, 24],
      overline: [53, 55],
      inverse: [7, 27],
      hidden: [8, 28],
      strikethrough: [9, 29]
    },
    color: {
      black: [30, 39],
      red: [31, 39],
      green: [32, 39],
      yellow: [33, 39],
      blue: [34, 39],
      magenta: [35, 39],
      cyan: [36, 39],
      white: [37, 39],
      blackBright: [90, 39],
      gray: [90, 39],
      grey: [90, 39],
      redBright: [91, 39],
      greenBright: [92, 39],
      yellowBright: [93, 39],
      blueBright: [94, 39],
      magentaBright: [95, 39],
      cyanBright: [96, 39],
      whiteBright: [97, 39]
    },
    bgColor: {
      bgBlack: [40, 49],
      bgRed: [41, 49],
      bgGreen: [42, 49],
      bgYellow: [43, 49],
      bgBlue: [44, 49],
      bgMagenta: [45, 49],
      bgCyan: [46, 49],
      bgWhite: [47, 49],
      bgBlackBright: [100, 49],
      bgGray: [100, 49],
      bgGrey: [100, 49],
      bgRedBright: [101, 49],
      bgGreenBright: [102, 49],
      bgYellowBright: [103, 49],
      bgBlueBright: [104, 49],
      bgMagentaBright: [105, 49],
      bgCyanBright: [106, 49],
      bgWhiteBright: [107, 49]
    }
  };
  var modifierNames = Object.keys(styles.modifier);
  var foregroundColorNames = Object.keys(styles.color);
  var backgroundColorNames = Object.keys(styles.bgColor);
  var colorNames = [...foregroundColorNames, ...backgroundColorNames];
  function assembleStyles() {
    const codes = /* @__PURE__ */ new Map();
    for (const [groupName, group] of Object.entries(styles)) {
      for (const [styleName, style] of Object.entries(group)) {
        styles[styleName] = {
          open: `\x1B[${style[0]}m`,
          close: `\x1B[${style[1]}m`
        };
        group[styleName] = styles[styleName];
        codes.set(style[0], style[1]);
      }
      Object.defineProperty(styles, groupName, {
        value: group,
        enumerable: false
      });
    }
    Object.defineProperty(styles, "codes", {
      value: codes,
      enumerable: false
    });
    styles.color.close = "\x1B[39m";
    styles.bgColor.close = "\x1B[49m";
    styles.color.ansi = wrapAnsi16();
    styles.color.ansi256 = wrapAnsi256();
    styles.color.ansi16m = wrapAnsi16m();
    styles.bgColor.ansi = wrapAnsi16(ANSI_BACKGROUND_OFFSET);
    styles.bgColor.ansi256 = wrapAnsi256(ANSI_BACKGROUND_OFFSET);
    styles.bgColor.ansi16m = wrapAnsi16m(ANSI_BACKGROUND_OFFSET);
    Object.defineProperties(styles, {
      rgbToAnsi256: {
        value(red, green, blue) {
          if (red === green && green === blue) {
            if (red < 8) {
              return 16;
            }
            if (red > 248) {
              return 231;
            }
            return Math.round((red - 8) / 247 * 24) + 232;
          }
          return 16 + 36 * Math.round(red / 255 * 5) + 6 * Math.round(green / 255 * 5) + Math.round(blue / 255 * 5);
        },
        enumerable: false
      },
      hexToRgb: {
        value(hex) {
          const matches = /[a-f\d]{6}|[a-f\d]{3}/i.exec(hex.toString(16));
          if (!matches) {
            return [0, 0, 0];
          }
          let [colorString] = matches;
          if (colorString.length === 3) {
            colorString = [...colorString].map((character) => character + character).join("");
          }
          const integer = Number.parseInt(colorString, 16);
          return [
            integer >> 16 & 255,
            integer >> 8 & 255,
            integer & 255
          ];
        },
        enumerable: false
      },
      hexToAnsi256: {
        value: (hex) => styles.rgbToAnsi256(...styles.hexToRgb(hex)),
        enumerable: false
      },
      ansi256ToAnsi: {
        value(code) {
          if (code < 8) {
            return 30 + code;
          }
          if (code < 16) {
            return 90 + (code - 8);
          }
          let red;
          let green;
          let blue;
          if (code >= 232) {
            red = ((code - 232) * 10 + 8) / 255;
            green = red;
            blue = red;
          } else {
            code -= 16;
            const remainder = code % 36;
            red = Math.floor(code / 36) / 5;
            green = Math.floor(remainder / 6) / 5;
            blue = remainder % 6 / 5;
          }
          const value = Math.max(red, green, blue) * 2;
          if (value === 0) {
            return 30;
          }
          let result = 30 + (Math.round(blue) << 2 | Math.round(green) << 1 | Math.round(red));
          if (value === 2) {
            result += 60;
          }
          return result;
        },
        enumerable: false
      },
      rgbToAnsi: {
        value: (red, green, blue) => styles.ansi256ToAnsi(styles.rgbToAnsi256(red, green, blue)),
        enumerable: false
      },
      hexToAnsi: {
        value: (hex) => styles.ansi256ToAnsi(styles.hexToAnsi256(hex)),
        enumerable: false
      }
    });
    return styles;
  }
  var ansiStyles = assembleStyles();
  var ansi_styles_default = ansiStyles;

  // ../../../.yarn/cache/chalk-npm-5.3.0-d181999efb-6373caaab2.zip/node_modules/chalk/source/vendor/supports-color/index.js
  var import_node_process = __toESM(__require("process"), 1);
  var import_node_os = __toESM(__require("os"), 1);
  var import_node_tty = __toESM(__require("tty"), 1);
  function hasFlag(flag, argv = globalThis.Deno ? globalThis.Deno.args : import_node_process.default.argv) {
    const prefix = flag.startsWith("-") ? "" : flag.length === 1 ? "-" : "--";
    const position = argv.indexOf(prefix + flag);
    const terminatorPosition = argv.indexOf("--");
    return position !== -1 && (terminatorPosition === -1 || position < terminatorPosition);
  }
  var { env } = import_node_process.default;
  var flagForceColor;
  if (hasFlag("no-color") || hasFlag("no-colors") || hasFlag("color=false") || hasFlag("color=never")) {
    flagForceColor = 0;
  } else if (hasFlag("color") || hasFlag("colors") || hasFlag("color=true") || hasFlag("color=always")) {
    flagForceColor = 1;
  }
  function envForceColor() {
    if ("FORCE_COLOR" in env) {
      if (env.FORCE_COLOR === "true") {
        return 1;
      }
      if (env.FORCE_COLOR === "false") {
        return 0;
      }
      return env.FORCE_COLOR.length === 0 ? 1 : Math.min(Number.parseInt(env.FORCE_COLOR, 10), 3);
    }
  }
  function translateLevel(level) {
    if (level === 0) {
      return false;
    }
    return {
      level,
      hasBasic: true,
      has256: level >= 2,
      has16m: level >= 3
    };
  }
  function _supportsColor(haveStream, { streamIsTTY, sniffFlags = true } = {}) {
    const noFlagForceColor = envForceColor();
    if (noFlagForceColor !== void 0) {
      flagForceColor = noFlagForceColor;
    }
    const forceColor = sniffFlags ? flagForceColor : noFlagForceColor;
    if (forceColor === 0) {
      return 0;
    }
    if (sniffFlags) {
      if (hasFlag("color=16m") || hasFlag("color=full") || hasFlag("color=truecolor")) {
        return 3;
      }
      if (hasFlag("color=256")) {
        return 2;
      }
    }
    if ("TF_BUILD" in env && "AGENT_NAME" in env) {
      return 1;
    }
    if (haveStream && !streamIsTTY && forceColor === void 0) {
      return 0;
    }
    const min = forceColor || 0;
    if (env.TERM === "dumb") {
      return min;
    }
    if (import_node_process.default.platform === "win32") {
      const osRelease = import_node_os.default.release().split(".");
      if (Number(osRelease[0]) >= 10 && Number(osRelease[2]) >= 10586) {
        return Number(osRelease[2]) >= 14931 ? 3 : 2;
      }
      return 1;
    }
    if ("CI" in env) {
      if ("GITHUB_ACTIONS" in env || "GITEA_ACTIONS" in env) {
        return 3;
      }
      if (["TRAVIS", "CIRCLECI", "APPVEYOR", "GITLAB_CI", "BUILDKITE", "DRONE"].some((sign) => sign in env) || env.CI_NAME === "codeship") {
        return 1;
      }
      return min;
    }
    if ("TEAMCITY_VERSION" in env) {
      return /^(9\.(0*[1-9]\d*)\.|\d{2,}\.)/.test(env.TEAMCITY_VERSION) ? 1 : 0;
    }
    if (env.COLORTERM === "truecolor") {
      return 3;
    }
    if (env.TERM === "xterm-kitty") {
      return 3;
    }
    if ("TERM_PROGRAM" in env) {
      const version = Number.parseInt((env.TERM_PROGRAM_VERSION || "").split(".")[0], 10);
      switch (env.TERM_PROGRAM) {
        case "iTerm.app": {
          return version >= 3 ? 3 : 2;
        }
        case "Apple_Terminal": {
          return 2;
        }
      }
    }
    if (/-256(color)?$/i.test(env.TERM)) {
      return 2;
    }
    if (/^screen|^xterm|^vt100|^vt220|^rxvt|color|ansi|cygwin|linux/i.test(env.TERM)) {
      return 1;
    }
    if ("COLORTERM" in env) {
      return 1;
    }
    return min;
  }
  function createSupportsColor(stream, options = {}) {
    const level = _supportsColor(stream, {
      streamIsTTY: stream && stream.isTTY,
      ...options
    });
    return translateLevel(level);
  }
  var supportsColor = {
    stdout: createSupportsColor({ isTTY: import_node_tty.default.isatty(1) }),
    stderr: createSupportsColor({ isTTY: import_node_tty.default.isatty(2) })
  };
  var supports_color_default = supportsColor;

  // ../../../.yarn/cache/chalk-npm-5.3.0-d181999efb-6373caaab2.zip/node_modules/chalk/source/utilities.js
  function stringReplaceAll(string, substring, replacer) {
    let index = string.indexOf(substring);
    if (index === -1) {
      return string;
    }
    const substringLength = substring.length;
    let endIndex = 0;
    let returnValue = "";
    do {
      returnValue += string.slice(endIndex, index) + substring + replacer;
      endIndex = index + substringLength;
      index = string.indexOf(substring, endIndex);
    } while (index !== -1);
    returnValue += string.slice(endIndex);
    return returnValue;
  }
  function stringEncaseCRLFWithFirstIndex(string, prefix, postfix, index) {
    let endIndex = 0;
    let returnValue = "";
    do {
      const gotCR = string[index - 1] === "\r";
      returnValue += string.slice(endIndex, gotCR ? index - 1 : index) + prefix + (gotCR ? "\r\n" : "\n") + postfix;
      endIndex = index + 1;
      index = string.indexOf("\n", endIndex);
    } while (index !== -1);
    returnValue += string.slice(endIndex);
    return returnValue;
  }

  // ../../../.yarn/cache/chalk-npm-5.3.0-d181999efb-6373caaab2.zip/node_modules/chalk/source/index.js
  var { stdout: stdoutColor, stderr: stderrColor } = supports_color_default;
  var GENERATOR = Symbol("GENERATOR");
  var STYLER = Symbol("STYLER");
  var IS_EMPTY = Symbol("IS_EMPTY");
  var levelMapping = [
    "ansi",
    "ansi",
    "ansi256",
    "ansi16m"
  ];
  var styles2 = /* @__PURE__ */ Object.create(null);
  var applyOptions = (object, options = {}) => {
    if (options.level && !(Number.isInteger(options.level) && options.level >= 0 && options.level <= 3)) {
      throw new Error("The `level` option should be an integer from 0 to 3");
    }
    const colorLevel = stdoutColor ? stdoutColor.level : 0;
    object.level = options.level === void 0 ? colorLevel : options.level;
  };
  var chalkFactory = (options) => {
    const chalk2 = (...strings) => strings.join(" ");
    applyOptions(chalk2, options);
    Object.setPrototypeOf(chalk2, createChalk.prototype);
    return chalk2;
  };
  function createChalk(options) {
    return chalkFactory(options);
  }
  Object.setPrototypeOf(createChalk.prototype, Function.prototype);
  for (const [styleName, style] of Object.entries(ansi_styles_default)) {
    styles2[styleName] = {
      get() {
        const builder = createBuilder(this, createStyler(style.open, style.close, this[STYLER]), this[IS_EMPTY]);
        Object.defineProperty(this, styleName, { value: builder });
        return builder;
      }
    };
  }
  styles2.visible = {
    get() {
      const builder = createBuilder(this, this[STYLER], true);
      Object.defineProperty(this, "visible", { value: builder });
      return builder;
    }
  };
  var getModelAnsi = (model, level, type, ...arguments_) => {
    if (model === "rgb") {
      if (level === "ansi16m") {
        return ansi_styles_default[type].ansi16m(...arguments_);
      }
      if (level === "ansi256") {
        return ansi_styles_default[type].ansi256(ansi_styles_default.rgbToAnsi256(...arguments_));
      }
      return ansi_styles_default[type].ansi(ansi_styles_default.rgbToAnsi(...arguments_));
    }
    if (model === "hex") {
      return getModelAnsi("rgb", level, type, ...ansi_styles_default.hexToRgb(...arguments_));
    }
    return ansi_styles_default[type][model](...arguments_);
  };
  var usedModels = ["rgb", "hex", "ansi256"];
  for (const model of usedModels) {
    styles2[model] = {
      get() {
        const { level } = this;
        return function(...arguments_) {
          const styler = createStyler(getModelAnsi(model, levelMapping[level], "color", ...arguments_), ansi_styles_default.color.close, this[STYLER]);
          return createBuilder(this, styler, this[IS_EMPTY]);
        };
      }
    };
    const bgModel = "bg" + model[0].toUpperCase() + model.slice(1);
    styles2[bgModel] = {
      get() {
        const { level } = this;
        return function(...arguments_) {
          const styler = createStyler(getModelAnsi(model, levelMapping[level], "bgColor", ...arguments_), ansi_styles_default.bgColor.close, this[STYLER]);
          return createBuilder(this, styler, this[IS_EMPTY]);
        };
      }
    };
  }
  var proto = Object.defineProperties(() => {
  }, {
    ...styles2,
    level: {
      enumerable: true,
      get() {
        return this[GENERATOR].level;
      },
      set(level) {
        this[GENERATOR].level = level;
      }
    }
  });
  var createStyler = (open, close, parent) => {
    let openAll;
    let closeAll;
    if (parent === void 0) {
      openAll = open;
      closeAll = close;
    } else {
      openAll = parent.openAll + open;
      closeAll = close + parent.closeAll;
    }
    return {
      open,
      close,
      openAll,
      closeAll,
      parent
    };
  };
  var createBuilder = (self, _styler, _isEmpty) => {
    const builder = (...arguments_) => applyStyle(builder, arguments_.length === 1 ? "" + arguments_[0] : arguments_.join(" "));
    Object.setPrototypeOf(builder, proto);
    builder[GENERATOR] = self;
    builder[STYLER] = _styler;
    builder[IS_EMPTY] = _isEmpty;
    return builder;
  };
  var applyStyle = (self, string) => {
    if (self.level <= 0 || !string) {
      return self[IS_EMPTY] ? "" : string;
    }
    let styler = self[STYLER];
    if (styler === void 0) {
      return string;
    }
    const { openAll, closeAll } = styler;
    if (string.includes("\x1B")) {
      while (styler !== void 0) {
        string = stringReplaceAll(string, styler.close, styler.open);
        styler = styler.parent;
      }
    }
    const lfIndex = string.indexOf("\n");
    if (lfIndex !== -1) {
      string = stringEncaseCRLFWithFirstIndex(string, closeAll, openAll, lfIndex);
    }
    return openAll + string + closeAll;
  };
  Object.defineProperties(createChalk.prototype, styles2);
  var chalk = createChalk();
  var chalkStderr = createChalk({ level: stderrColor ? stderrColor.level : 0 });
  var source_default = chalk;

  // ../../../.yarn/cache/widest-line-npm-4.0.1-e0740b8930-64c48cf271.zip/node_modules/widest-line/index.js
  function widestLine(string) {
    let lineWidth = 0;
    for (const line of string.split("\n")) {
      lineWidth = Math.max(lineWidth, stringWidth(line));
    }
    return lineWidth;
  }

  // ../../../.yarn/cache/boxen-npm-7.1.1-e79a50b11c-a21d514435.zip/node_modules/boxen/index.js
  var import_cli_boxes = __toESM(require_cli_boxes(), 1);

  // ../../../.yarn/cache/camelcase-npm-7.0.1-d41d97bb0d-86ab8f3ebf.zip/node_modules/camelcase/index.js
  var UPPERCASE = /[\p{Lu}]/u;
  var LOWERCASE = /[\p{Ll}]/u;
  var LEADING_CAPITAL = /^[\p{Lu}](?![\p{Lu}])/gu;
  var IDENTIFIER = /([\p{Alpha}\p{N}_]|$)/u;
  var SEPARATORS = /[_.\- ]+/;
  var LEADING_SEPARATORS = new RegExp("^" + SEPARATORS.source);
  var SEPARATORS_AND_IDENTIFIER = new RegExp(SEPARATORS.source + IDENTIFIER.source, "gu");
  var NUMBERS_AND_IDENTIFIER = new RegExp("\\d+" + IDENTIFIER.source, "gu");
  var preserveCamelCase = (string, toLowerCase, toUpperCase, preserveConsecutiveUppercase2) => {
    let isLastCharLower = false;
    let isLastCharUpper = false;
    let isLastLastCharUpper = false;
    let isLastLastCharPreserved = false;
    for (let index = 0; index < string.length; index++) {
      const character = string[index];
      isLastLastCharPreserved = index > 2 ? string[index - 3] === "-" : true;
      if (isLastCharLower && UPPERCASE.test(character)) {
        string = string.slice(0, index) + "-" + string.slice(index);
        isLastCharLower = false;
        isLastLastCharUpper = isLastCharUpper;
        isLastCharUpper = true;
        index++;
      } else if (isLastCharUpper && isLastLastCharUpper && LOWERCASE.test(character) && (!isLastLastCharPreserved || preserveConsecutiveUppercase2)) {
        string = string.slice(0, index - 1) + "-" + string.slice(index - 1);
        isLastLastCharUpper = isLastCharUpper;
        isLastCharUpper = false;
        isLastCharLower = true;
      } else {
        isLastCharLower = toLowerCase(character) === character && toUpperCase(character) !== character;
        isLastLastCharUpper = isLastCharUpper;
        isLastCharUpper = toUpperCase(character) === character && toLowerCase(character) !== character;
      }
    }
    return string;
  };
  var preserveConsecutiveUppercase = (input, toLowerCase) => {
    LEADING_CAPITAL.lastIndex = 0;
    return input.replace(LEADING_CAPITAL, (m1) => toLowerCase(m1));
  };
  var postProcess = (input, toUpperCase) => {
    SEPARATORS_AND_IDENTIFIER.lastIndex = 0;
    NUMBERS_AND_IDENTIFIER.lastIndex = 0;
    return input.replace(SEPARATORS_AND_IDENTIFIER, (_, identifier) => toUpperCase(identifier)).replace(NUMBERS_AND_IDENTIFIER, (m) => toUpperCase(m));
  };
  function camelCase(input, options) {
    if (!(typeof input === "string" || Array.isArray(input))) {
      throw new TypeError("Expected the input to be `string | string[]`");
    }
    options = {
      pascalCase: false,
      preserveConsecutiveUppercase: false,
      ...options
    };
    if (Array.isArray(input)) {
      input = input.map((x) => x.trim()).filter((x) => x.length).join("-");
    } else {
      input = input.trim();
    }
    if (input.length === 0) {
      return "";
    }
    const toLowerCase = options.locale === false ? (string) => string.toLowerCase() : (string) => string.toLocaleLowerCase(options.locale);
    const toUpperCase = options.locale === false ? (string) => string.toUpperCase() : (string) => string.toLocaleUpperCase(options.locale);
    if (input.length === 1) {
      if (SEPARATORS.test(input)) {
        return "";
      }
      return options.pascalCase ? toUpperCase(input) : toLowerCase(input);
    }
    const hasUpperCase = input !== toLowerCase(input);
    if (hasUpperCase) {
      input = preserveCamelCase(input, toLowerCase, toUpperCase, options.preserveConsecutiveUppercase);
    }
    input = input.replace(LEADING_SEPARATORS, "");
    input = options.preserveConsecutiveUppercase ? preserveConsecutiveUppercase(input, toLowerCase) : toLowerCase(input);
    if (options.pascalCase) {
      input = toUpperCase(input.charAt(0)) + input.slice(1);
    }
    return postProcess(input, toUpperCase);
  }

  // ../../../.yarn/cache/boxen-npm-7.1.1-e79a50b11c-a21d514435.zip/node_modules/boxen/index.js
  var import_ansi_align = __toESM(require_ansi_align(), 1);

  // ../../../.yarn/cache/ansi-styles-npm-6.2.1-d43647018c-70fdf883b7.zip/node_modules/ansi-styles/index.js
  var ANSI_BACKGROUND_OFFSET2 = 10;
  var wrapAnsi162 = (offset = 0) => (code) => `\x1B[${code + offset}m`;
  var wrapAnsi2562 = (offset = 0) => (code) => `\x1B[${38 + offset};5;${code}m`;
  var wrapAnsi16m2 = (offset = 0) => (red, green, blue) => `\x1B[${38 + offset};2;${red};${green};${blue}m`;
  var styles3 = {
    modifier: {
      reset: [0, 0],
      bold: [1, 22],
      dim: [2, 22],
      italic: [3, 23],
      underline: [4, 24],
      overline: [53, 55],
      inverse: [7, 27],
      hidden: [8, 28],
      strikethrough: [9, 29]
    },
    color: {
      black: [30, 39],
      red: [31, 39],
      green: [32, 39],
      yellow: [33, 39],
      blue: [34, 39],
      magenta: [35, 39],
      cyan: [36, 39],
      white: [37, 39],
      blackBright: [90, 39],
      gray: [90, 39],
      grey: [90, 39],
      redBright: [91, 39],
      greenBright: [92, 39],
      yellowBright: [93, 39],
      blueBright: [94, 39],
      magentaBright: [95, 39],
      cyanBright: [96, 39],
      whiteBright: [97, 39]
    },
    bgColor: {
      bgBlack: [40, 49],
      bgRed: [41, 49],
      bgGreen: [42, 49],
      bgYellow: [43, 49],
      bgBlue: [44, 49],
      bgMagenta: [45, 49],
      bgCyan: [46, 49],
      bgWhite: [47, 49],
      bgBlackBright: [100, 49],
      bgGray: [100, 49],
      bgGrey: [100, 49],
      bgRedBright: [101, 49],
      bgGreenBright: [102, 49],
      bgYellowBright: [103, 49],
      bgBlueBright: [104, 49],
      bgMagentaBright: [105, 49],
      bgCyanBright: [106, 49],
      bgWhiteBright: [107, 49]
    }
  };
  var modifierNames2 = Object.keys(styles3.modifier);
  var foregroundColorNames2 = Object.keys(styles3.color);
  var backgroundColorNames2 = Object.keys(styles3.bgColor);
  var colorNames2 = [...foregroundColorNames2, ...backgroundColorNames2];
  function assembleStyles2() {
    const codes = /* @__PURE__ */ new Map();
    for (const [groupName, group] of Object.entries(styles3)) {
      for (const [styleName, style] of Object.entries(group)) {
        styles3[styleName] = {
          open: `\x1B[${style[0]}m`,
          close: `\x1B[${style[1]}m`
        };
        group[styleName] = styles3[styleName];
        codes.set(style[0], style[1]);
      }
      Object.defineProperty(styles3, groupName, {
        value: group,
        enumerable: false
      });
    }
    Object.defineProperty(styles3, "codes", {
      value: codes,
      enumerable: false
    });
    styles3.color.close = "\x1B[39m";
    styles3.bgColor.close = "\x1B[49m";
    styles3.color.ansi = wrapAnsi162();
    styles3.color.ansi256 = wrapAnsi2562();
    styles3.color.ansi16m = wrapAnsi16m2();
    styles3.bgColor.ansi = wrapAnsi162(ANSI_BACKGROUND_OFFSET2);
    styles3.bgColor.ansi256 = wrapAnsi2562(ANSI_BACKGROUND_OFFSET2);
    styles3.bgColor.ansi16m = wrapAnsi16m2(ANSI_BACKGROUND_OFFSET2);
    Object.defineProperties(styles3, {
      rgbToAnsi256: {
        value: (red, green, blue) => {
          if (red === green && green === blue) {
            if (red < 8) {
              return 16;
            }
            if (red > 248) {
              return 231;
            }
            return Math.round((red - 8) / 247 * 24) + 232;
          }
          return 16 + 36 * Math.round(red / 255 * 5) + 6 * Math.round(green / 255 * 5) + Math.round(blue / 255 * 5);
        },
        enumerable: false
      },
      hexToRgb: {
        value: (hex) => {
          const matches = /[a-f\d]{6}|[a-f\d]{3}/i.exec(hex.toString(16));
          if (!matches) {
            return [0, 0, 0];
          }
          let [colorString] = matches;
          if (colorString.length === 3) {
            colorString = [...colorString].map((character) => character + character).join("");
          }
          const integer = Number.parseInt(colorString, 16);
          return [
            integer >> 16 & 255,
            integer >> 8 & 255,
            integer & 255
          ];
        },
        enumerable: false
      },
      hexToAnsi256: {
        value: (hex) => styles3.rgbToAnsi256(...styles3.hexToRgb(hex)),
        enumerable: false
      },
      ansi256ToAnsi: {
        value: (code) => {
          if (code < 8) {
            return 30 + code;
          }
          if (code < 16) {
            return 90 + (code - 8);
          }
          let red;
          let green;
          let blue;
          if (code >= 232) {
            red = ((code - 232) * 10 + 8) / 255;
            green = red;
            blue = red;
          } else {
            code -= 16;
            const remainder = code % 36;
            red = Math.floor(code / 36) / 5;
            green = Math.floor(remainder / 6) / 5;
            blue = remainder % 6 / 5;
          }
          const value = Math.max(red, green, blue) * 2;
          if (value === 0) {
            return 30;
          }
          let result = 30 + (Math.round(blue) << 2 | Math.round(green) << 1 | Math.round(red));
          if (value === 2) {
            result += 60;
          }
          return result;
        },
        enumerable: false
      },
      rgbToAnsi: {
        value: (red, green, blue) => styles3.ansi256ToAnsi(styles3.rgbToAnsi256(red, green, blue)),
        enumerable: false
      },
      hexToAnsi: {
        value: (hex) => styles3.ansi256ToAnsi(styles3.hexToAnsi256(hex)),
        enumerable: false
      }
    });
    return styles3;
  }
  var ansiStyles2 = assembleStyles2();
  var ansi_styles_default2 = ansiStyles2;

  // ../../../.yarn/cache/wrap-ansi-npm-8.1.0-26a4e6ae28-7b1e4b35e9.zip/node_modules/wrap-ansi/index.js
  var ESCAPES = /* @__PURE__ */ new Set([
    "\x1B",
    "\x9B"
  ]);
  var END_CODE = 39;
  var ANSI_ESCAPE_BELL = "\x07";
  var ANSI_CSI = "[";
  var ANSI_OSC = "]";
  var ANSI_SGR_TERMINATOR = "m";
  var ANSI_ESCAPE_LINK = `${ANSI_OSC}8;;`;
  var wrapAnsiCode = (code) => `${ESCAPES.values().next().value}${ANSI_CSI}${code}${ANSI_SGR_TERMINATOR}`;
  var wrapAnsiHyperlink = (uri) => `${ESCAPES.values().next().value}${ANSI_ESCAPE_LINK}${uri}${ANSI_ESCAPE_BELL}`;
  var wordLengths = (string) => string.split(" ").map((character) => stringWidth(character));
  var wrapWord = (rows, word, columns) => {
    const characters = [...word];
    let isInsideEscape = false;
    let isInsideLinkEscape = false;
    let visible = stringWidth(stripAnsi(rows[rows.length - 1]));
    for (const [index, character] of characters.entries()) {
      const characterLength = stringWidth(character);
      if (visible + characterLength <= columns) {
        rows[rows.length - 1] += character;
      } else {
        rows.push(character);
        visible = 0;
      }
      if (ESCAPES.has(character)) {
        isInsideEscape = true;
        isInsideLinkEscape = characters.slice(index + 1).join("").startsWith(ANSI_ESCAPE_LINK);
      }
      if (isInsideEscape) {
        if (isInsideLinkEscape) {
          if (character === ANSI_ESCAPE_BELL) {
            isInsideEscape = false;
            isInsideLinkEscape = false;
          }
        } else if (character === ANSI_SGR_TERMINATOR) {
          isInsideEscape = false;
        }
        continue;
      }
      visible += characterLength;
      if (visible === columns && index < characters.length - 1) {
        rows.push("");
        visible = 0;
      }
    }
    if (!visible && rows[rows.length - 1].length > 0 && rows.length > 1) {
      rows[rows.length - 2] += rows.pop();
    }
  };
  var stringVisibleTrimSpacesRight = (string) => {
    const words = string.split(" ");
    let last = words.length;
    while (last > 0) {
      if (stringWidth(words[last - 1]) > 0) {
        break;
      }
      last--;
    }
    if (last === words.length) {
      return string;
    }
    return words.slice(0, last).join(" ") + words.slice(last).join("");
  };
  var exec = (string, columns, options = {}) => {
    if (options.trim !== false && string.trim() === "") {
      return "";
    }
    let returnValue = "";
    let escapeCode;
    let escapeUrl;
    const lengths = wordLengths(string);
    let rows = [""];
    for (const [index, word] of string.split(" ").entries()) {
      if (options.trim !== false) {
        rows[rows.length - 1] = rows[rows.length - 1].trimStart();
      }
      let rowLength = stringWidth(rows[rows.length - 1]);
      if (index !== 0) {
        if (rowLength >= columns && (options.wordWrap === false || options.trim === false)) {
          rows.push("");
          rowLength = 0;
        }
        if (rowLength > 0 || options.trim === false) {
          rows[rows.length - 1] += " ";
          rowLength++;
        }
      }
      if (options.hard && lengths[index] > columns) {
        const remainingColumns = columns - rowLength;
        const breaksStartingThisLine = 1 + Math.floor((lengths[index] - remainingColumns - 1) / columns);
        const breaksStartingNextLine = Math.floor((lengths[index] - 1) / columns);
        if (breaksStartingNextLine < breaksStartingThisLine) {
          rows.push("");
        }
        wrapWord(rows, word, columns);
        continue;
      }
      if (rowLength + lengths[index] > columns && rowLength > 0 && lengths[index] > 0) {
        if (options.wordWrap === false && rowLength < columns) {
          wrapWord(rows, word, columns);
          continue;
        }
        rows.push("");
      }
      if (rowLength + lengths[index] > columns && options.wordWrap === false) {
        wrapWord(rows, word, columns);
        continue;
      }
      rows[rows.length - 1] += word;
    }
    if (options.trim !== false) {
      rows = rows.map((row) => stringVisibleTrimSpacesRight(row));
    }
    const pre = [...rows.join("\n")];
    for (const [index, character] of pre.entries()) {
      returnValue += character;
      if (ESCAPES.has(character)) {
        const { groups } = new RegExp(`(?:\\${ANSI_CSI}(?<code>\\d+)m|\\${ANSI_ESCAPE_LINK}(?<uri>.*)${ANSI_ESCAPE_BELL})`).exec(pre.slice(index).join("")) || { groups: {} };
        if (groups.code !== void 0) {
          const code2 = Number.parseFloat(groups.code);
          escapeCode = code2 === END_CODE ? void 0 : code2;
        } else if (groups.uri !== void 0) {
          escapeUrl = groups.uri.length === 0 ? void 0 : groups.uri;
        }
      }
      const code = ansi_styles_default2.codes.get(Number(escapeCode));
      if (pre[index + 1] === "\n") {
        if (escapeUrl) {
          returnValue += wrapAnsiHyperlink("");
        }
        if (escapeCode && code) {
          returnValue += wrapAnsiCode(code);
        }
      } else if (character === "\n") {
        if (escapeCode && code) {
          returnValue += wrapAnsiCode(escapeCode);
        }
        if (escapeUrl) {
          returnValue += wrapAnsiHyperlink(escapeUrl);
        }
      }
    }
    return returnValue;
  };
  function wrapAnsi(string, columns, options) {
    return String(string).normalize().replace(/\r\n/g, "\n").split("\n").map((line) => exec(line, columns, options)).join("\n");
  }

  // ../../../.yarn/cache/boxen-npm-7.1.1-e79a50b11c-a21d514435.zip/node_modules/boxen/index.js
  var import_cli_boxes2 = __toESM(require_cli_boxes(), 1);
  var NEWLINE = "\n";
  var PAD = " ";
  var NONE = "none";
  var terminalColumns = () => {
    const { env: env2, stdout, stderr } = import_node_process2.default;
    if (stdout?.columns) {
      return stdout.columns;
    }
    if (stderr?.columns) {
      return stderr.columns;
    }
    if (env2.COLUMNS) {
      return Number.parseInt(env2.COLUMNS, 10);
    }
    return 80;
  };
  var getObject = (detail) => typeof detail === "number" ? {
    top: detail,
    right: detail * 3,
    bottom: detail,
    left: detail * 3
  } : {
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    ...detail
  };
  var getBorderWidth = (borderStyle) => borderStyle === NONE ? 0 : 2;
  var getBorderChars = (borderStyle) => {
    const sides = [
      "topLeft",
      "topRight",
      "bottomRight",
      "bottomLeft",
      "left",
      "right",
      "top",
      "bottom"
    ];
    let characters;
    if (borderStyle === NONE) {
      borderStyle = {};
      for (const side of sides) {
        borderStyle[side] = "";
      }
    }
    if (typeof borderStyle === "string") {
      characters = import_cli_boxes.default[borderStyle];
      if (!characters) {
        throw new TypeError(`Invalid border style: ${borderStyle}`);
      }
    } else {
      if (typeof borderStyle?.vertical === "string") {
        borderStyle.left = borderStyle.vertical;
        borderStyle.right = borderStyle.vertical;
      }
      if (typeof borderStyle?.horizontal === "string") {
        borderStyle.top = borderStyle.horizontal;
        borderStyle.bottom = borderStyle.horizontal;
      }
      for (const side of sides) {
        if (borderStyle[side] === null || typeof borderStyle[side] !== "string") {
          throw new TypeError(`Invalid border style: ${side}`);
        }
      }
      characters = borderStyle;
    }
    return characters;
  };
  var makeTitle = (text, horizontal, alignment) => {
    let title = "";
    const textWidth = stringWidth(text);
    switch (alignment) {
      case "left": {
        title = text + horizontal.slice(textWidth);
        break;
      }
      case "right": {
        title = horizontal.slice(textWidth) + text;
        break;
      }
      default: {
        horizontal = horizontal.slice(textWidth);
        if (horizontal.length % 2 === 1) {
          horizontal = horizontal.slice(Math.floor(horizontal.length / 2));
          title = horizontal.slice(1) + text + horizontal;
        } else {
          horizontal = horizontal.slice(horizontal.length / 2);
          title = horizontal + text + horizontal;
        }
        break;
      }
    }
    return title;
  };
  var makeContentText = (text, { padding, width, textAlignment, height }) => {
    text = (0, import_ansi_align.default)(text, { align: textAlignment });
    let lines = text.split(NEWLINE);
    const textWidth = widestLine(text);
    const max = width - padding.left - padding.right;
    if (textWidth > max) {
      const newLines = [];
      for (const line of lines) {
        const createdLines = wrapAnsi(line, max, { hard: true });
        const alignedLines = (0, import_ansi_align.default)(createdLines, { align: textAlignment });
        const alignedLinesArray = alignedLines.split("\n");
        const longestLength = Math.max(...alignedLinesArray.map((s) => stringWidth(s)));
        for (const alignedLine of alignedLinesArray) {
          let paddedLine;
          switch (textAlignment) {
            case "center": {
              paddedLine = PAD.repeat((max - longestLength) / 2) + alignedLine;
              break;
            }
            case "right": {
              paddedLine = PAD.repeat(max - longestLength) + alignedLine;
              break;
            }
            default: {
              paddedLine = alignedLine;
              break;
            }
          }
          newLines.push(paddedLine);
        }
      }
      lines = newLines;
    }
    if (textAlignment === "center" && textWidth < max) {
      lines = lines.map((line) => PAD.repeat((max - textWidth) / 2) + line);
    } else if (textAlignment === "right" && textWidth < max) {
      lines = lines.map((line) => PAD.repeat(max - textWidth) + line);
    }
    const paddingLeft = PAD.repeat(padding.left);
    const paddingRight = PAD.repeat(padding.right);
    lines = lines.map((line) => paddingLeft + line + paddingRight);
    lines = lines.map((line) => {
      if (width - stringWidth(line) > 0) {
        switch (textAlignment) {
          case "center": {
            return line + PAD.repeat(width - stringWidth(line));
          }
          case "right": {
            return line + PAD.repeat(width - stringWidth(line));
          }
          default: {
            return line + PAD.repeat(width - stringWidth(line));
          }
        }
      }
      return line;
    });
    if (padding.top > 0) {
      lines = [...Array.from({ length: padding.top }).fill(PAD.repeat(width)), ...lines];
    }
    if (padding.bottom > 0) {
      lines = [...lines, ...Array.from({ length: padding.bottom }).fill(PAD.repeat(width))];
    }
    if (height && lines.length > height) {
      lines = lines.slice(0, height);
    } else if (height && lines.length < height) {
      lines = [...lines, ...Array.from({ length: height - lines.length }).fill(PAD.repeat(width))];
    }
    return lines.join(NEWLINE);
  };
  var boxContent = (content, contentWidth, options) => {
    const colorizeBorder = (border) => {
      const newBorder = options.borderColor ? getColorFn(options.borderColor)(border) : border;
      return options.dimBorder ? source_default.dim(newBorder) : newBorder;
    };
    const colorizeContent = (content2) => options.backgroundColor ? getBGColorFn(options.backgroundColor)(content2) : content2;
    const chars = getBorderChars(options.borderStyle);
    const columns = terminalColumns();
    let marginLeft = PAD.repeat(options.margin.left);
    if (options.float === "center") {
      const marginWidth = Math.max((columns - contentWidth - getBorderWidth(options.borderStyle)) / 2, 0);
      marginLeft = PAD.repeat(marginWidth);
    } else if (options.float === "right") {
      const marginWidth = Math.max(columns - contentWidth - options.margin.right - getBorderWidth(options.borderStyle), 0);
      marginLeft = PAD.repeat(marginWidth);
    }
    let result = "";
    if (options.margin.top) {
      result += NEWLINE.repeat(options.margin.top);
    }
    if (options.borderStyle !== NONE || options.title) {
      result += colorizeBorder(marginLeft + chars.topLeft + (options.title ? makeTitle(options.title, chars.top.repeat(contentWidth), options.titleAlignment) : chars.top.repeat(contentWidth)) + chars.topRight) + NEWLINE;
    }
    const lines = content.split(NEWLINE);
    result += lines.map((line) => marginLeft + colorizeBorder(chars.left) + colorizeContent(line) + colorizeBorder(chars.right)).join(NEWLINE);
    if (options.borderStyle !== NONE) {
      result += NEWLINE + colorizeBorder(marginLeft + chars.bottomLeft + chars.bottom.repeat(contentWidth) + chars.bottomRight);
    }
    if (options.margin.bottom) {
      result += NEWLINE.repeat(options.margin.bottom);
    }
    return result;
  };
  var sanitizeOptions = (options) => {
    if (options.fullscreen && import_node_process2.default?.stdout) {
      let newDimensions = [import_node_process2.default.stdout.columns, import_node_process2.default.stdout.rows];
      if (typeof options.fullscreen === "function") {
        newDimensions = options.fullscreen(...newDimensions);
      }
      if (!options.width) {
        options.width = newDimensions[0];
      }
      if (!options.height) {
        options.height = newDimensions[1];
      }
    }
    if (options.width) {
      options.width = Math.max(1, options.width - getBorderWidth(options.borderStyle));
    }
    if (options.height) {
      options.height = Math.max(1, options.height - getBorderWidth(options.borderStyle));
    }
    return options;
  };
  var formatTitle = (title, borderStyle) => borderStyle === NONE ? title : ` ${title} `;
  var determineDimensions = (text, options) => {
    options = sanitizeOptions(options);
    const widthOverride = options.width !== void 0;
    const columns = terminalColumns();
    const borderWidth = getBorderWidth(options.borderStyle);
    const maxWidth = columns - options.margin.left - options.margin.right - borderWidth;
    const widest = widestLine(wrapAnsi(text, columns - borderWidth, { hard: true, trim: false })) + options.padding.left + options.padding.right;
    if (options.title && widthOverride) {
      options.title = options.title.slice(0, Math.max(0, options.width - 2));
      if (options.title) {
        options.title = formatTitle(options.title, options.borderStyle);
      }
    } else if (options.title) {
      options.title = options.title.slice(0, Math.max(0, maxWidth - 2));
      if (options.title) {
        options.title = formatTitle(options.title, options.borderStyle);
        if (stringWidth(options.title) > widest) {
          options.width = stringWidth(options.title);
        }
      }
    }
    options.width = options.width ? options.width : widest;
    if (!widthOverride) {
      if (options.margin.left && options.margin.right && options.width > maxWidth) {
        const spaceForMargins = columns - options.width - borderWidth;
        const multiplier = spaceForMargins / (options.margin.left + options.margin.right);
        options.margin.left = Math.max(0, Math.floor(options.margin.left * multiplier));
        options.margin.right = Math.max(0, Math.floor(options.margin.right * multiplier));
      }
      options.width = Math.min(options.width, columns - borderWidth - options.margin.left - options.margin.right);
    }
    if (options.width - (options.padding.left + options.padding.right) <= 0) {
      options.padding.left = 0;
      options.padding.right = 0;
    }
    if (options.height && options.height - (options.padding.top + options.padding.bottom) <= 0) {
      options.padding.top = 0;
      options.padding.bottom = 0;
    }
    return options;
  };
  var isHex = (color) => color.match(/^#(?:[0-f]{3}){1,2}$/i);
  var isColorValid = (color) => typeof color === "string" && (source_default[color] ?? isHex(color));
  var getColorFn = (color) => isHex(color) ? source_default.hex(color) : source_default[color];
  var getBGColorFn = (color) => isHex(color) ? source_default.bgHex(color) : source_default[camelCase(["bg", color])];
  function boxen(text, options) {
    options = {
      padding: 0,
      borderStyle: "single",
      dimBorder: false,
      textAlignment: "left",
      float: "left",
      titleAlignment: "left",
      ...options
    };
    if (options.align) {
      options.textAlignment = options.align;
    }
    if (options.borderColor && !isColorValid(options.borderColor)) {
      throw new Error(`${options.borderColor} is not a valid borderColor`);
    }
    if (options.backgroundColor && !isColorValid(options.backgroundColor)) {
      throw new Error(`${options.backgroundColor} is not a valid backgroundColor`);
    }
    options.padding = getObject(options.padding);
    options.margin = getObject(options.margin);
    options = determineDimensions(text, options);
    text = makeContentText(text, options);
    return boxContent(text, options.width, options);
  }

  // sources/index.ts
  var import_find_up = __toESM(require_find_up());
  function findPackagesNeedSoftLink(tomlPath) {
    const foundryConfig = import_toml.default.parse(fs.readFileSync(tomlPath, "utf-8"));
    const softLinkPackages = [];
    for (const profileName in foundryConfig["profile"]) {
      const profileConfig = foundryConfig["profile"][profileName];
      const remappings = profileConfig["remappings"] || [];
      const packages = remappings.filter((mapItem) => mapItem.match(/=node_modules\/*/g)).map((mapItem) => mapItem.split("=")[0].replace(/\/$/, ""));
      softLinkPackages.push(...packages);
    }
    return softLinkPackages;
  }
  function ensureDir(dir) {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }
  function ensureSymlink(target, path2) {
    if (fs.existsSync(path2)) {
      try {
        if (fs.realpathSync(path2) === target) {
          return;
        }
        fs.unlinkSync(path2);
      } catch (e) {
        if (!(e instanceof Error && e.code === "ENOENT")) {
          throw e;
        }
      }
    }
    try {
      fs.symlinkSync(target, path2, "dir");
    } catch (e) {
      if (!(e instanceof Error && e.code === "EEXIST")) {
        throw e;
      }
    }
  }
  async function resolve(packageName, workspace) {
    const project = workspace.project;
    const workspacePkg = workspace.project.storedPackages.get(workspace.anchoredLocator.locatorHash);
    const identHash = import_core.structUtils.parseIdent(packageName).identHash;
    const workspaceDescriptor = project.workspacesByIdent.get(identHash)?.anchoredDescriptor;
    const descriptor2 = workspaceDescriptor || workspacePkg.dependencies.get(identHash);
    if (!descriptor2) {
      throw new Error(`${packageName} is not installed in ${import_core.structUtils.stringifyIdent(workspace.locator)}`);
    }
    const locatorHash = project.storedResolutions.get(descriptor2.descriptorHash);
    const pkg = project.storedPackages.get(locatorHash);
    const linker = project.configuration.getLinkers().find((linker2) => linker2.supportsPackage(pkg, { project }));
    if (!linker) {
      throw new Error(`No linker supports ${import_core.structUtils.stringifyIdent(pkg)}`);
    }
    const pkgPath = await linker.findPackageLocation(pkg, {
      project,
      report: new import_core.ThrowReport()
    });
    if (!workspaceDescriptor && !project.getDependencyMeta(pkg, null)?.unplugged) {
      throw new Error(`${import_core.structUtils.stringifyIdent(pkg)} is not set as unplugged`);
    }
    return pkgPath;
  }
  async function createSoftLinkForForge(project) {
    const { configuration } = project;
    const tomlPath = (0, import_find_up.sync)("foundry.toml", { cwd: configuration.startingCwd });
    if (!tomlPath) {
      return;
    }
    const packageNames = findPackagesNeedSoftLink(tomlPath);
    if (packageNames.length > 0) {
      const workspace = project.getWorkspaceByCwd(path.dirname(tomlPath));
      const errors = [];
      for (const packageName of packageNames) {
        try {
          const packageDir = await resolve(packageName, workspace);
          const linkPath = path.join(path.dirname(tomlPath), "node_modules", packageName);
          ensureDir(path.dirname(linkPath));
          ensureSymlink(packageDir.toString(), linkPath);
        } catch (e) {
          errors.push(e.message);
        }
      }
      if (errors.length > 0) {
        console.log(
          boxen(errors.join("\n"), {
            title: "Foundry Remapping Error",
            titleAlignment: "center",
            padding: 1,
            borderColor: "red",
            width: 120
          })
        );
        process4.exit(1);
      }
    }
  }
  var plugin = {
    hooks: {
      wrapScriptExecution: (executor, project, locator, scriptName, extra) => {
        const func = async () => {
          if (extra.script.includes("forge ")) {
            await createSoftLinkForForge(project);
          }
          return executor;
        };
        return func();
      }
    }
  };
  var sources_default = plugin;
  return __toCommonJS(sources_exports);
})();
return plugin;
}
};
