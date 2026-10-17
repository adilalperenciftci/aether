- **A `-> ptr` function returning a string literal returns its
  characters.** Since 0.818.0 every literal is a pinned counted string,
  and a literal used as a `ptr` is meant to stay its C characters; one
  passed straight to a `ptr` parameter was, but `return "constructor"`
  from a `-> ptr` function, or a local or parameter holding a literal,
  returned the pinned string's header, so C reading the result read its
  bytes (`strlen` gave 9, not 11). A pinned string returned as a `ptr` is
  now its characters; a counted string is still handed over as itself, as
  #2945 moves it. Found by mquickjs-ae.
