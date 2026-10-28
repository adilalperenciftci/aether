- **A panic in a library export ends the call, not the host, and nested
  calls give the outer call its state back.** A panic an `--emit=lib`
  export did not catch printed "panic outside any try/catch or actor" and
  aborted the process that loaded the library. Every export now runs in an
  execution frame: the panic ends the call with `AETHER_PANICKED`, the
  export returns its zero value, `aether_last_outcome()` and
  `aether_last_outcome_text()` (libaether.h) say how the call ended, and
  the library takes the next call. An export that called a host service,
  which set another caller and deadline and called an export again, saw the
  inner call's caller and deadline from then on, and a sandbox level the
  inner call left pushed stayed in force; each call now has its own, and
  the outer one's are back when the inner one returns, however it ends. An
  Aether program importing a library in binary form gets a failed call
  raised again as a panic with the same reason, which a `try` catches, and
  `host.last_outcome()` / `host.last_outcome_text()` read the outcome. A
  library built with its own runtime now carries the host API
  (`aether_set_call_deadline`, `aether_set_memory_cap`,
  `aether_deadline_tripped`, `aether_set_caller`, ...) even when its code
  calls none of it: a DLL had no `aether_set_call_deadline`, so a host could
  not bound its calls. Every catalog is schema "1.10", with `outcome`
  naming the library's outcome accessor; on Windows dbghelp is loaded when
  a panic's stack trace is printed, so a C host needs no `-ldbghelp`. The
  frame costs the context save a catchable panic needs: an export that
  calls a function is 5.7 ns a call on Windows MinGW against 0.4 ns
  before (the stub saves with `__builtin_setjmp` on x86, and Win64 makes it
  keep its callee-saved registers), fib(30) through its stub is unchanged,
  and an export that can neither panic, allocate, loop nor call anything
  gets no frame (0.57 ns against 0.19 ns). A `try` frame no longer calls
  into the allocation journal when it is pushed (#2955, #2956).
