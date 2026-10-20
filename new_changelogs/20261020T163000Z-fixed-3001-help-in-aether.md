- **What a diagnostic suggests is Aether.** The `@scoped` escape error
  suggested `buf.len()`, which Aether does not have; its help now names a
  value derived from the binding for its type (`string.length(buf)` for a
  string, `list.size(l)` for a list, `v.len` for a slice). A sweep of the
  other help texts fixed three more: a function that returns nothing,
  assigned, suggested the return type `g(...): int` (it is `-> int`); an
  arm with no value suggested `{ g(...)  0 }` (now `{ g(...); 0 }`); a bare
  ptr given to a slice parameter pointed at an `array()` view (it is
  `intarr.array(a)`). The `@scoped` container check listed `list.push`,
  `map.set` and `seq.cons`, which std does not have, and missed
  `string.seq_cons` and the raw and owning inserts; and the language server
  completed nine std calls that do not exist (`math.abs`, `log.info`,
  `json.stringify`, `cryptography.sha256`, the base64 calls under
  std.cryptography rather than std.encoding, ...) (#3001).
