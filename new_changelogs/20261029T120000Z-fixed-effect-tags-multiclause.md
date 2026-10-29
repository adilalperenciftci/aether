- **Effect tags now cover every clause of a function.** `@pure`, `@no_fs`,
  `@no_net`, and `@no_os` no longer accept a function when a later pattern
  clause, or a later clause of a transitive callee, reaches a forbidden
  capability.
