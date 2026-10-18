- **A string passed to a slice parameter is a type error at the call.**
  `cryptography.sha256_hex("abc")`, or any string literal or string local
  given to a `byte[]` (or other `T[]`) parameter, type-checked and then
  produced C that did not compile: a `const char*` where an `AetherSlice`
  is expected. An extern's `byte[]` parameter got the counted string's
  header, not its bytes. A binding and a `return` already refused a
  string there, since a string is not a slice. The call now refuses it
  too, and for a `byte[]` slot the diagnostic names `string.bytes(s)`,
  the string's bytes as a bounded view.
