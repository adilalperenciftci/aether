- **Migrating from 0.838: a function that puts a borrowed `ptr` parameter
  in a std container declares it `@keep`.** What a call keeps is read from
  the callee's declaration, never from the name it spells (#3079, #3086).
  std's list and map stores declare their item `@retain` at the C
  boundary: `list.add`, `list.add_raw`, `list.set`, `map.put` and
  `map.put_raw` (and their `collections.` spellings, now externs over C
  functions of the same names, with the same results), and `string.seq_cons`
  its head and its tail. A borrowed `ptr` parameter put in a list or a map
  is E0902, as one stored in a module `var` is; on 0.838.0 only a closure
  or a struct holding one was checked, and `collections.list_add(routes,
  box_closure(cb))` not even that, while a program's own `list_add` that
  kept nothing was refused.

  ```aether
  remember(p: ptr) { _r = list.add(seen, p) }        // E0902: the list keeps `p`
  remember(p: @keep ptr) { _r = list.add(seen, p) }  // the parameter says it is kept
  ```

  A list or a map the function makes itself and lets go nowhere is no
  such place: the stores name the container that holds what they keep
  (`@holds`), the constructors say their result is fresh (`@fresh`), and
  a borrowed `ptr` parked in such a worklist keeps nothing past the call.

  A `fn?` parameter, and a struct or sum parameter one of whose fields or
  variants holds a closure or a `ptr` (an optional of one included), are
  borrowed as a `fn` parameter is. `@scoped` reads the same declarations:
  a value given to a parameter that keeps it escapes, including
  `string.seq_cons`'s tail; one given to `set.add`, which copies it, does
  not. `collections.map_put_string_owned` declared its copied key
  `@retain`, so a counted key handed the map a reference it never released
  (std.map declared the same function without it, so which applied
  depended on import order); the key is borrowed now.
