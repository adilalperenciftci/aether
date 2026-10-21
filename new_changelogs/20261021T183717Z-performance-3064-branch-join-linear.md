- **A function that binds a local many times compiles in linear time
  again.** 0.838.0 joined a local's bindings as an if-expression's
  branches join by walking the whole function body at every binding of
  it, so a body bound n times cost n walks: a `main` with `x = x + i`
  6000 times took 4.9 s to compile, 12000 times 24.7 s. The join is kept
  as the bindings are typed now, with the same answers: 0.12 s and 0.31 s
  (#3064).
