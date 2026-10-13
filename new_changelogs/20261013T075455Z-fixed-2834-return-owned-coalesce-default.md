- **Returning `w ?? d` no longer frees `d` first.** With `d` a parameter
  the function captures (it escapes through that return) or a local bound
  to a heap string, `return w ?? d` read `d`, then the scope-exit free gave
  it back and the caller got the freed pointer. Such a return makes the
  function heap-returning now, and the value taken is copied (#2834).
