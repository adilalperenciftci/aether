- **A scalar variable beside a lane value splats, as a literal does.** The
  language reference says a scalar operand splats, and the type checker
  accepted `v * s` for an `f32x4` `v` and a `float` `s`, but the generated
  `v * s` put a C `double` beside a vector of `float`, which clang and GCC
  reject ("implicit conversion would cause truncation"); only a literal,
  being a constant, compiled. The scalar is now converted to the lane's
  element type before C broadcasts it, for `f32x4`, `f64x2`, `i32x4`,
  `i64x2` and `i16x8` (`f32x8` / `i32x8` already splatted through their
  helpers), for every arithmetic and comparison operator, with the scalar on
  either side, in a compound assignment (`v *= s`), and through a distinct
  type over a lane type (`type vec4 = distinct f32x4`).
