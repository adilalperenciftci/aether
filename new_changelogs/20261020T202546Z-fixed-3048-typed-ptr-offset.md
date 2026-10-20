- **A typed pointer moved by an integer keeps its type.** With `nodes` a
  `*Node`, `nodes + 2` (or `nodes - n`, `n + nodes`) was typed a bare
  `ptr`, so `(nodes + 2).w` passed the checker and failed in the C
  compiler ("request for member 'w' in something not a structure or
  union"). It is a `*Node` now, and its fields read and write; with
  `nodes = base as *Node` and a `long` offset it was E0200, and is
  accepted too. A field read or stored through a bare `ptr`, which has no
  fields, is the checker's error now: view it as the struct it points at
  first, `(p as *Node).w` (#3048).
