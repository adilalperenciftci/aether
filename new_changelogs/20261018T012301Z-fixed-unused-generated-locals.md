- **More generated locals no longer break a `-Wall -Werror` build.** Some
  locals the C declared were never read, which is `-Wunused-variable` under
  `-Wall` on gcc and clang:
  - a closure env's teardown with nothing to release (`_e`);
  - an actor arm that binds no field (`_pattern`), or binds one it never
    reads;
  - a `_`-prefixed or never-read local (`_x = 5`), including a `_ = f()`
    hoisted out of a loop;
  - a match whose arms are all `_` (`_match_val`);
  - a list pattern's unread tail length.

  Each is now followed by `(void)name;`, as a destructure's unread local
  already is. Across the C generated from `tests/` and `examples/`, clang's
  `-Wunused-variable` count drops from 709 to 10.
