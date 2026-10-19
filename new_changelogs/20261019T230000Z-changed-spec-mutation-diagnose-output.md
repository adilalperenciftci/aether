- **std.spec failure messages, std.mutation's summary and the
  `--diagnose=ownership` note use plain punctuation and the current model.**
  A matcher given an intent message prints `<why>: <detail>` (it printed an
  em dash between them) in std.spec, std.os.testing and
  std.http.client.httptest; std.mutation prints `3/3 mutants killed,
  mutation score 100%` and `(N excluded: did not compile)`. A tool that
  matched the old text matches these. `aetherc --diagnose=ownership` ended
  with a note about lines "marked KEPT ALIVE", which no line ever was, and
  advised `@noescape`; it now says what `move` and `take` do and that an
  extern which keeps a string declares the parameter `@retain`.
