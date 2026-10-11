- **A catch binding a nested `try` writes keeps what was stored before
  its panic.** The handler declared the binding and its ownership flag
  plain, so a `try` inside the handler that rebound it
  (`e = string.concat(e, w)`) and then panicked left the two holding their
  values from before at -O2: the string stored was lost, or freed twice. A
  variable is now volatile wherever a `try` nested deeper than its
  declaration writes it, the catch binding of a handler included (#2739).
