- **Passing a parameter on to a `string?` tuple position copies nothing
  extra.** A named function hands its `string?` tuple positions over owned,
  a copy, but the keep analysis took them for keeping the parameter, so a
  function that passed its parameter to one copied it on entry and leaked
  the copy; and a returned tuple local holding such a call's result was
  copied, its own string leaked (#2867).
