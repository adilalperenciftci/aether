- **`string.new_with_length(s, n)` of an Aether string copies its
  characters.** The C function copied `data` as given, so for a counted or
  pinned string (a literal, anything an Aether program holds) it copied the
  string's header bytes instead of its text. It reads the string's
  characters now, and no more of them than the string holds (#3030).
