- **A builder setter whose parameter carries a `where` contract gets the
  trailing block's `_ctx`.** `set_n(_ctx: ptr, n: int where n >= 0)` called
  as `set_n(3)` inside a builder block went out without `_ctx`, and gcc
  reported too few arguments: the contract is kept among the function's
  children as a requires clause, and the count that decides whether to inject
  `_ctx` took it for a parameter. It counts parameters only now (#2706).
