- **A glob import binds every export of a wide module.** The table that maps
  each bare name an import binds to the qualified name its calls are
  rewritten to held 512 entries and dropped the rest without a word. A glob
  import of a module with more exports (aether-ui's `ui` has about 700) left
  the dropped names bound for the checker but not rewritten, so the program
  type-checked and its C called `window(...)`, `vstack(...)` and `text(...)`
  bare and undeclared, where importing the same names selectively built. The
  table now grows as needed.
