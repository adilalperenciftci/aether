- **`ae fmt` writes `make([]fn, 2)` tight.** A slice's element type is
  written against its `[]` (`[]int`, `[]*Node`), but `fn`, the one type
  that is a keyword, was taken for a keyword and spaced: `make([] fn, 2)`
  (#3081).
