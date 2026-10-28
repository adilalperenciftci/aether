- **A call's deadline ends the call, and another thread can cancel one.**
  A deadline set with `aether_set_call_deadline` broke the loop it was
  checked in, and the export returned whatever the loop had, an
  ordinary-looking value only `aether_deadline_tripped()` said was partial;
  a JSON parse had no check at all and ran to the end of a large document;
  and
  nothing could stop a call from another thread. Inside an export, the
  first safe point past the deadline now ends the call: the interruption
  unwinds like a panic, every frame on the way runs its defers and releases
  its owned locals, a `try` passes it on after its own cleanup instead of
  running its handler, and the export returns its zero value with the
  outcome `AETHER_DEADLINE`. `aether_exec_token()` names the call running
  on a thread (or its next one), and `aether_exec_cancel(token)` from any
  thread ends that call the same way with `AETHER_CANCELLED`; a cancel of a
  call that already ended does nothing. The safe points are loop heads and
  `json.parse`, every 4096 values; straight-line code, recursion without a
  loop (a safe point at every function entry made fib(30) 71% slower, so
  there is none), other C-backed std operations and `extern` calls run to
  their end (docs/emit-lib.md, "Per-call resource caps"). On Windows
  MinGW, an execution's record was cleared by a store into the
  thread-local's template instead of the calling thread's copy (GCC 16.2
  at -O2 merges two adjacent stores into an extern thread-local aggregate
  and addresses the merged one through the variable's non-thread
  address), so a call could keep the next-deadline and caller-info flags
  of an earlier call at the same depth: the per-thread frames block is now
  a `static` thread-local of `aether_unwind.c`, reached from every other
  file through `aether_frames_here()` (#2956).
