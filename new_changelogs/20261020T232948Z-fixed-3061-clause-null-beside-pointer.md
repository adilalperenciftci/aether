- **A clause that returns only `null` takes the pointer, string or closure
  type beside it.** In a clause set, `node_or_null(0, p: *Node) -> null`
  beside `node_or_null(k, p: *Node) -> p`, or `label(0) -> null` beside
  `label(k) -> "many"`, the `null` clause is a slot of the other clause's
  type, as a binding of that type takes `null`; beside an int it is E0200
  naming both. A `null` returned from a function whose result is a closure
  is the empty closure, as one stored or passed is (#3061, #3062).
