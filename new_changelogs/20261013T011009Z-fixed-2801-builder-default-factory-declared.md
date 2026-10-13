- **A builder with the default config factory builds without `import
  std.map`.** Its calls are lowered to `map_new()`, which nothing declared
  unless the program imported std.map, so a program whose builder never
  touched its config failed in the C compiler ("implicit declaration of
  function 'map_new'"). The generated C now declares `map_new` and
  `map_free` whenever a builder uses the default factory (#2801).
