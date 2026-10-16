- **A string literal costs nothing to store.** A literal is a static pinned
  string, but storing one still ran the general take: a run-time probe of
  its header, and for `list.add` the adopting entry and a release probe of
  its result. Taking a literal is now the literal itself, `list.add` adds it
  as an element the list does not own, and the pinned strings are `const`,
  so the C compiler folds a probe of one away. The `list.add` of a literal
  micro-benchmark went from 44.3% to 3.1% over the release before #2916
  (#2925).
