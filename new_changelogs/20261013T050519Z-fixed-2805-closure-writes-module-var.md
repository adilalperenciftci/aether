- **A closure writes a module-level `var` itself.** A closure that wrote a
  module `var` (`set = || { gnum = 11 }`) turned the name into a cell of
  the enclosing function's own, for the whole function: neither the
  closure's stores nor the function's own `gnum = 9` reached the global,
  so the function saw one value and every other function the old one. A
  closure that read one took a copy. A module `var` is never captured now:
  the closure reads and writes the global, and only a parameter of the
  same name, which shadows it, is captured (#2805).
