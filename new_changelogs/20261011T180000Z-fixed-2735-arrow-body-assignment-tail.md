- **An arrow body that ends in an assignment stores and returns nothing.**
  An assignment is a statement, and a trailing statement is not a value
  (#2694), but the arrow rule returned every trailing binding:
  `bump() -> { hits = hits + 1 }` emitted `return hits + 1;`, so `hits`
  never changed, `-> { a += 3 }` did not compile (`return +=3;`), and a new
  local last (`-> { label = "b=${n}" }`) failed in the C compiler. A body
  ending in `x = v` (a new local or an existing one), `x += v`, `p.n = v`,
  `xs[i] = v` or a send now ends with that statement, for a function or a
  closure, and so does the single expression form `-> n = n + 1`, whose
  store a closure lost. A `match` last is a value only when one of its arms
  gives one; one whose arms all call functions that return nothing is a
  statement, where it emitted a C return of a void value (#2735).
