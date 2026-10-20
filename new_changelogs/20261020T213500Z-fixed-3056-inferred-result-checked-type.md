- **A function with no written result type returns what it returns.** One
  whose `return` value the early inference pass could not type (a field
  read through a pointer, among others) was given an int result: `return
  ps.n + big` with a long `big` came back truncated with no word, and a
  string field read that way failed in the C compiler. Such a function now
  takes the checked type of its first value `return`, and is checked
  before its callers, so each call has that type wherever it is written;
  an erased call's int (`call(f)`) is still a default, not a result type
  (#3056).
