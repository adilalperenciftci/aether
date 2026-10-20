- **A value returned from a `T!` function is checked against `T`.** One
  value from a `-> int!` function is its success value, which the result
  wraps, and it went unchecked: `return s` with `s` a string passed the
  checker and failed in the C compiler. It is now checked as a `-> int`
  return is, arm by arm in a branching value, with the same conversions (an
  int into a `long!` or a `float!`); a result forwarded whole and a value
  propagated by `!` pass as before, and `return value, err` is unchanged
  (#3044).
