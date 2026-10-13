- **docs/quote.md says what type a lane has in a quote's tree.** It said
  `uv.x * 10.0` was a `float`; the tree says `f32`, as the checker types
  `.x` of any `f32x4` or distinct type over one. `f32` is the honest answer
  (Aether's `float` is a C double, and a lane holds a 32-bit float), so the
  tree stays as it is: docs/quote.md and std/quote's README now say the
  types are Aether's spellings and a GLSL back end maps both `float` and
  `f32` to GLSL's `float`, and `test_quote_fxaa.ae` holds the lane type.
