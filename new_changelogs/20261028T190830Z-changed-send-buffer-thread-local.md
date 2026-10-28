- **The send buffer is no longer an extern thread-local.** `g_send_buffer`,
  a thread-local of several fields declared in `aether_send_buffer.h` and
  written field by field from every file that buffered a send, is now a
  `static` thread-local of `aether_send_buffer.c`, reached through
  `send_buffer_here()`. GCC 16.2 for x86_64-w64-mingw32 at -O2 merged two
  adjacent stores into an extern thread-local aggregate into one store
  addressed through the variable's non-thread address, so the calling
  thread's copy kept its old value (the per-thread frames block was hit;
  the send buffer's code was not, yet). The rule, written at
  `aether_frames.h`: an extern thread-local is a scalar written whole; an
  aggregate stays static to its file, reached by accessor. `send_buffered()`
  stays inline, writing through the pointer: 1.57 ns a buffered send
  against 1.55 ns before on Windows MinGW, loops aligned (5.7 ns as a call,
  the message copied twice). Fixes #3372. `runtime/examples/buffered_send_bench.c` no longer hangs in its
  second benchmark: it stopped the scheduler without a shutdown, and
  `scheduler_init()` does nothing on a scheduler that is only stopped; and
  its actor took up to 128 messages a step where the scheduler counts one,
  so a shutdown waited for messages it would never see handled.
