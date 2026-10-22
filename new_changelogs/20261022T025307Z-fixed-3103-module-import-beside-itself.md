- **A module's own import names the file beside it, wherever the compiler
  runs.** A program built in a directory with a `parser.ae` of its own
  (contrib/jq) and importing `std.jsonpath` failed: "'free_query' is not
  exported from module 'parser'". std.jsonpath's `import parser` searched
  the current directory before its own, and found the program's file. A
  module's own imports look beside it first now; the entry program's keep
  the project root first. contrib/jq's `_str_indices` no longer leaks its
  result for an empty needle, and jq, std.jsonpath, liquid and four
  examples build without their W1002 warnings (#3103).
