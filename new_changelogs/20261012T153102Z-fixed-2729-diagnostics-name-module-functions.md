- **The effect-tag error names a module's function as the source does.** An
  `@pure` (or `@no_os`, ...) function of an imported module reaching a
  disallowed call was named by its merged C name, `checks_shell`, instead of
  `checks.shell`. It and the always-false `requires` error now name it as a
  caller writes it, through the helper the missing-return error used (#2729).
