- **A receive arm that names a field its message lacks is an error at the
  arm.** An arm binds a message's fields by name (`Connect(next)`, or
  `Connect(next: n)` to bind the field `next` as `n`); `Connect(n)`, a
  positional reading, went on with `n` untyped and the generated C failed,
  "'Connect' has no member named 'n'". It is now E0200 at the `n`, "message
  'Connect' has no field 'n'; its fields are next", with the rename form as
  its help, and the reference says how an arm binds (#3164).
