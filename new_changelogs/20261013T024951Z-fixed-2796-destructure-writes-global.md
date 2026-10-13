- **A tuple destructure writes a module-level `var`.** `gx, n = two()` in a
  function declared a local `gx` and left the global as it was, where a
  bare `gx = 7` writes it. The slot writes the global now, taking the value
  as a global takes one: a string of its own, and a reference of its own
  to a closure, giving back the one it held. A local or parameter of the
  same name still shadows the global (#2796).
