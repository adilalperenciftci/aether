- **A string local a `try` body writes keeps what was stored before a
  panic.** Such a local must be volatile for its value to survive the
  longjmp of a panic, and so must the flag that says whether it owns its
  string. A local declared ahead of its first binding (a string, optional
  string or `*StringSeq` local, declared at the function's entry, or one
  first bound in the arms of an `if`) was declared plain, with its flag,
  so after a caught panic both could hold their values from before the
  `try`: the string stored was lost, or freed as if never owned. A string
  stored inside a `try` into a local declared outside it was also
  journaled for the try's own frame, so the panic freed it while the local
  still held it, and the code after the catch read freed memory. Both are
  volatile now, and the string is journaled for the frame the local is
  declared in, so the local frees it where its scope ends (#2690).
