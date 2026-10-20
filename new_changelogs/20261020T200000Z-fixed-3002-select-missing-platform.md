- **A `select()` with no value for a platform is error E0701.** With no
  `other:` fallback, `select(linux: 8080)` printed an `error:` line with no
  code from codegen and the build went on into C, which stopped at the
  `#error` written in the missing value's place. The type checker now
  refuses it, naming the platforms with no value and the branches given,
  and no C is written. The generated C serves every platform, so the rule
  is the same whatever the build targets; a defined build-symbol key still
  decides a select outright (#3002).
