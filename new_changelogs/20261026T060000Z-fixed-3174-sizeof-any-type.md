- **`sizeof` takes any type a declaration takes.** Its operand was read as
  one identifier, so `sizeof(int)` was "'int' is a reserved keyword and
  cannot be used as an identifier", `sizeof(gpu.Shader)` stopped at the
  dot, and a width name became a struct in the C (`sizeof(uint32)` was
  `sizeof(struct uint32)`). The operand is now read by the type parser:
  keyword types, widths, pointers, fixed-size arrays, structs (bare or
  qualified), enums and distinct types each give the size C gives the type
  they lower to, in a `const` too. `offsetof` takes a struct, bare or
  qualified; another type is one error at the type, and a `sizeof` of
  something that is not a type says so (#3174).
