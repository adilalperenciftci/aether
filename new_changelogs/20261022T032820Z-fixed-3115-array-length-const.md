- **An array length may be a named constant or an expression over them.**
  The parser took only a decimal number and read it with `atoi`, so
  `long[QWORDS]` beside `const QWORDS: int = 128` and `long[NW + 1]` were
  syntax errors, `byte[0x40]` was an array of length 0, and `int[0]`
  compiled as a slice. A length is now an integer constant expression (a
  literal in any base, a `const` of the file, `+ - * / % << >>` and
  parentheses), at least 1, in every place a type is written, and anything
  else is an error that says what a length may be (#3115).
