- **A variable a `try` body writes keeps what was stored before a
  panic.** Such a variable must be volatile for its value to survive the
  longjmp of a panic, and so must the flag that says whether it owns its
  string. A local declared ahead of its first binding (a string, optional
  string or `*StringSeq` local, declared at the function's entry, or one
  first bound in the arms of an `if` or a loop) was declared plain, with
  its flag, and so were a parameter, a closure's parameter, a message
  pattern binding and a local declared inside one `try` and written in a
  nested one. After a caught panic they could hold their values from
  before the `try` (at -O2 with `ae build`): a string parameter was its
  caller's string again while its flag said the function owned it, so the
  function freed its caller's string (heap corruption), and a string
  stored was lost or freed as if never owned. A string stored inside a
  `try` into a local declared outside it was also journaled for the try's
  own frame, so the panic freed it while the local still held it, and the
  code after the catch read freed memory. All are volatile now, a
  parameter in the function's own signature, and the string is journaled
  for the frame the local is declared in, so the local frees it where its
  scope ends. A struct value so declared is released and replaced through
  `<Name>_destroy_volatile` and `<Name>_replace_volatile`, which take its
  volatile pointer: the plain ones warned (`-Wdiscarded-qualifiers`), as
  did a store into a field of an element of such an array. Each function,
  closure and receive arm marks its own try-written names; they were
  carried from one arm or closure to the next, which made an unrelated
  local volatile. Also fixed on the way: a struct that owns strings,
  declared ahead of the `if` it is first bound in, is destroyed where it
  is declared (it leaked what it held at the end), and a `string` state
  field assigned a message's string is no longer widened to `void*` (the
  store warned) (#2690).
