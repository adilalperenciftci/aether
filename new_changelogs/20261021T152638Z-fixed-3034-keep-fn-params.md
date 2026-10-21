- **Migrating from 0.837: a function that keeps a closure declares it
  `@keep fn`.** E0902 now checks a `fn` parameter, and a struct parameter
  taken by value that holds a `ptr` or a closure, as it checks a `ptr` one,
  against the function's own body. A closure given to a function that kept
  it went unchecked, so one that captured a borrowed `ptr` outlived the
  call holding it.

  ```aether
  on_event(cb: fn) { handlers = box_closure(cb) }        // E0902: the function keeps `cb`
  on_event(cb: @keep fn) { handlers = box_closure(cb) }  // the parameter says it is kept
  ```

  A function keeps a parameter when it stores it where it outlives the
  call, boxes it there, puts it in a container (a `list_add` or `map_put`
  included), or passes it to a parameter that keeps it; calling it, handing
  it to a borrowing parameter or returning it keeps nothing, and neither
  does a store into memory the function allocates and frees, for any
  parameter. A caller is checked against the declaration: a closure that
  captures a borrowed `ptr`, given to a `@keep fn` parameter, is E0902
  there. The declaration changes no count (the call borrows the closure, the
  callee's store takes its own reference). `box_closure(f)` now holds what
  `f` captured, so a boxed closure stored where it outlives the call is
  checked too. std and contrib declare what they keep: `worker.run`,
  `run_detached`, `set_main_poster` and `map`, `observe.observe` and
  `observe_fields`, `schema.refine`, `spec.before_each` and `after_each`,
  `quickjs.function`, and tinyweb's route, filter, websocket, SSE and
  `on_*` registrations. The language reference's string ownership section
  carries the same entry (#3034).
