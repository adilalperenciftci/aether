- **`ae fmt` keeps the space between a keyword and the array literal after
  it.** The formatter wrote no space before a `[` that followed any word
  token, taking it for an index, and a keyword is one: `return []` came out
  as `return[]` and `for x in [1, 2]` as `in[1, 2]`, so `ae fmt --check`
  rejected the spelling the language reference uses. An index follows a
  value (`xs[0]`, `f()[1]`) and `fn[2]` sizes an array type; after any other
  keyword the `[` opens a literal and keeps its space (#2787).
