- **An optional state field is stored by a handler's assignment.**
  `kept = bytes.new(4)` in a handler, for `state kept: ptr? = none`,
  declared a local of that name, which shadowed the state: the field stayed
  `none` and the value was lost (a buffer leaked). A field of any other type
  was stored. An optional state field is now stored as the others are,
  dropping what it held (#3300).
