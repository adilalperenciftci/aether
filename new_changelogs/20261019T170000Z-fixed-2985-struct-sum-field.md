- **A struct field can hold a sum type (#2985).** `struct Holder { sh:
  Shape }` failed in C with "unknown type name 'Shape'": every struct was
  emitted before every sum's typedef. Type definitions now go out in
  dependency order, a sum after the variant structs its union embeds and a
  struct after the sums its fields hold by value (directly or as an
  optional). A variant given to such a field, in a struct literal
  (`Holder { sh: Circle { r: 1.0 } }`) or a store (`h.sh = Rect { ... }`),
  is wrapped into the sum as a binding of the sum wraps it.
