- **A quote's helpers, and so `quote.hash`, are named the same in every
  program.** A `@quotable` function in a module was named in the tree by its
  merged C name, whose prefix is the module's last segment unless another
  loaded module ends the same way (#2209). So `ae3d.shaders.sky`'s
  `oct_decode` was `sky_oct_decode` in a program importing only it and
  `ae3d_shaders_sky_oct_decode` in one that also imports `ae3d.sky`, the
  same quote hashed differently in the two, and ae3d refused its
  precompiled SPIR-V. A module's helper is now named by the module's full
  path, dots as underscores, and the function, always
  (`ae3d_shaders_sky_oct_decode`, `shaderlib_luma`), in `HELPER_CALL`,
  `quote.function_name`, `quote.helper_named` and the hash; calls still
  reach the function's C name. `quote.VERSION` stays 2 (no kind changed),
  but helpers in a module of more than one segment are renamed and the hash
  of each quote reaching one changes once: regenerate anything cached on it.
