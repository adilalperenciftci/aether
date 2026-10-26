- **A destructure into an element reads its index first.** `xs[i], i =
  pair()` stored into the element the statement gave `i`, after the names
  were bound and after the value. An element's index is now evaluated
  first, left to right and before the value, as in Go: the element `i`
  named before the statement takes the value (#3208).
