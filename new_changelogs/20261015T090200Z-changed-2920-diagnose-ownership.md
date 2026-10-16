- **`aetherc --diagnose=ownership` reports the ownership model.** Each
  string store is listed as moved (a fresh value, or a local at its last
  use) or taken (retained; a literal costs nothing), and a local still
  handed to C where C may keep it is marked KEPT ALIVE. Every string
  function hands its caller one reference, so the HEAP / NOT HEAP verdicts
  are gone (#2920).
