- **Struct types belong to their module.** Two modules may each define a
  struct of one name, and a program may use both: `gpu.Shader` and
  `core.Shader` are two types, where before they were E0200 ("struct
  'Shader' is defined differently in two modules", #2129) and libraries had
  to prefix their struct names (ae3d's `GpuShader`) to stay clear of each
  other. A module's struct is emitted as `<ns>_<Name>` (`gpu_Shader`); the
  program's own structs keep their names. A struct name resolves where it is
  written, as a function's does: `gpu.Shader`, `*gpu.Shader` and
  `gpu.Shader { ... }` name gpu's, and a bare `Shader` is the file's own or
  the one among its imports, with a selective `import gpu (Shader)` picking
  between two; otherwise two candidates are an error naming both qualified
  spellings. Identical definitions in two modules still share one type.
  Diagnostics spell a module's struct qualified (`expected *core.Shader, got
  *gpu.Shader`); `@derive` names (`Shader_eq`), schema tables and quote trees
  keep the name as written, so a quote's hash does not change. In an
  `--emit=lib` build a struct its module exports keeps its plain C name, the
  library's ABI; only unexported module structs are mangled there.
