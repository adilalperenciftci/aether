- **`std.cbor` decodes untrusted input safely by default.** `parse` now
  refuses duplicate map keys (`cbor: duplicate map key "grant"`), where two
  keys are duplicates when they are the same value however they were encoded,
  and limits each array or map to 131072 elements or pairs. It also refuses a
  declared length or count that cannot fit in the bytes left before
  allocating for it. `parse_with(data, opts)` takes a `CborDecodeOptions`
  (`default_decode_options()` gives the defaults) to change the limits, allow
  duplicates, or refuse indefinite-length items. `encode_deterministic`
  writes RFC 8949 §4.2.1 core deterministic encoding: shortest forms, definite
  lengths and sorted map keys. Duplicate detection and key sorting are
  linear-logarithmic, so a map at the limit cannot be used to spend minutes
  of CPU. Refusing duplicate keys is a change to `parse`'s behaviour; use
  `parse_with` with `allow_duplicate_keys = 1` for the old one.
