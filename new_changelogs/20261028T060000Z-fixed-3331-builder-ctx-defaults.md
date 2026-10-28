- **A builder setter's defaulted parameters can be left out in its block.**
  Inside a builder's trailing block `_ctx` is injected and hidden from the
  caller, but the arity check counted it among the arguments the call
  gives: `item("a")` for `item(_ctx, name, kind = "plain")` was refused
  (E0200), and `item("b", "fancy")` was read as `_ctx = "b"` with `kind`
  defaulted, every argument one place off. In a block the call now gives
  the parameters after `_ctx` and the defaults fill the rest; a call that
  passes the context itself (`_ctx`, `builder_context()`) or every
  parameter passes it explicitly, as outside a block (#3331).
