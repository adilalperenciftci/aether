- **One rule for what can be printed.** Interpolation refused a value with
  no string rendering, but a tuple got through (`"${t}"` printed a number
  that changed from run to run), and `print` / `println` checked nothing:
  a struct, a sum or a tuple argument reached C as a `%d` and printed
  garbage, in the call, in the `print` statement and in print's format
  arguments. Every place that renders a value now applies one rule, and a
  tuple, a struct, a sum, an optional, an array, a function value or a call
  returning several values is error E0200, with the spelling that renders
  it (#3016). A `ptr` still renders as a C string until std stops typing
  strings as `ptr` (#3018).
