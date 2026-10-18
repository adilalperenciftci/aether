- **A glob import of std.string, std.list or std.map no longer hides the
  builtin `free` from other modules.** Since 0.805.0 a module's merged body
  does not see the program's imports: a bare name it finds through one is a
  name it never imported. The check asked whether the program imported the
  NAME, and the glob of a module defining `free` (`string.free`,
  `list.free`, `map.free`) names `free`, though the symbol a module found
  was the builtin, which the glob does not bind. So every module calling
  `free` undeclared, std.cryptography among them, was "Undefined function
  'free'" in a program with `import std.string (*)`. The check now asks
  whether the import bound the symbol, and a module's bare `free` is no
  longer rewritten to the program's `string.free`. Found by zsync-port.
