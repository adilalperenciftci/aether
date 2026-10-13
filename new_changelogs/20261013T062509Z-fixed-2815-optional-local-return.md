- **Returning `w ?? d` or `w!` from a `string?` local no longer returns
  freed memory.** The return read the string out of the local, the
  local's scope-exit free gave it back, and the caller got the freed
  pointer, which printed other strings' bytes once the block was reused.
  The function is heap-returning for such a return now and hands the
  caller a copy, the local freeing its own; a fresh default is handed
  over as it is. A tuple position does the same (#2815).
