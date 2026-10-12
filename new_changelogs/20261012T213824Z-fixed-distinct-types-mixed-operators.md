- **An operator does not mix two different distinct types.** Distinct types
  have nominal identity, enforced at assignments and call arguments, but
  `USD + EUR` (both `distinct float`) compiled and added the two, as did
  `vec3 + vec4` over the same lane type. A binary operator, comparison or
  compound assignment whose operands are two different distinct types is now
  a type error (E0200) naming both: `'+' mixes distinct types USD and EUR`.
  The same distinct type on both sides now keeps it (`USD + USD` is a `USD`,
  so `usd += usd` and passing the sum where a `USD` is wanted work without a
  cast; before, the result was the base `float`), and a distinct lane type
  scaled by a scalar keeps it (`vec4 * s` is a `vec4`). A distinct type
  beside a plain value of its base (`USD + 1.0`) is unchanged: computed over
  the base, the result is the base. See docs/distinct-types.md.
