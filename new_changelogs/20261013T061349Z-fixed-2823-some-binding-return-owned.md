- **Returning a `some(s)` binding no longer leaks.** In a function that
  matched a `string?` call result (or a `string?` closure cell of its own)
  and returned the `some(s)` binding beside a literal, `return s` handed
  over the binding's own string, but the function was classified as
  returning borrowed strings, so the caller never freed it: 37 bytes a
  call. The binding counts as a heap return now, and the literal beside
  it is copied (#2823).
