- **A panic no longer leaks an owned pointer it skips the release of.** A
  place of an owned pointer type (`type T = owned ptr drop f`), a function's
  local or an arm's binding of an owned message field, was released at its
  exits only: a panic skipped them, and the buffer leaked with its drop never
  run (an arm that bound the field and panicked leaked it every time). Every
  such place is now in the unwind journal while it lives, by one rule, and a
  panic releases it as its exit would (#3406).
