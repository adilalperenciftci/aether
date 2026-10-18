- **A quote names an array of a distinct type by its element.** A captured
  struct's `vec4[4]` field, where `vec4` is a distinct `f32x4`, was typed
  `UNKNOWN[4]` in the tree. The array was spelled through `type_to_string`,
  which has no name for a distinct type, while an `INDEX` of it was typed
  `vec4`. An array's element is now spelled as the tree spells any type, so
  the field is `vec4[4]`. A captured array of structs is now `Name[4]`, not
  `struct Name[4]`, as a struct alone already was. Found writing ae3d's
  composite.
