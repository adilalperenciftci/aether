- **`m.x` reaches a module's function written `m_x`.** A qualified name was
  resolved by joining it into the C name `m_x`, which reached an extern of
  that name and a function `x`, but not an Aether function the module names
  `m_x` (merged as `m_m_x`): std.md5's `md5.hex` and a module's
  `rexxae.create` for its `rexxae_create` were `E0301 Undefined function`,
  while `md5.md5_hex` built. Qualified names now resolve by the names the
  module declares, the plain one first and then the prefixed form, for
  every kind of declaration, in a call and in a selective import (#2976).
