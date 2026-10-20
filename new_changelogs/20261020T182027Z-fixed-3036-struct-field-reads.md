- **A field read out of a struct local holds only what went into that
  field.** A struct local holding a borrowed `ptr` parameter in one field
  counted as holding it in every field, so `s = Pair { a: p, b:
  malloc(8) }` then `return s.b` was E0902. A struct built from fields, by
  its literal or by stores into its fields (`s.b = q`, `s.in.b = q`), now
  records which field holds the parameter, nested ones included, and a
  field read (`s.b`, `s.in.b`) or a struct pattern's binding carries only
  what that field holds. A value whose parts hold more than eight
  parameter entries is taken as holding them as a whole, refusing more
  and never less (#3036).
