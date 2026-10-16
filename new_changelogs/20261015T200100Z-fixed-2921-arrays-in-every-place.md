- **A fixed-size array goes wherever a value goes.** A message field holds
  one by value and owns its elements; an optional wraps one
  (`let o: string[2]? = [...]`); an array literal of owning elements passed
  to a function is a temporary of its statement; one thrown away
  (`_ = [...]`) is dropped. These did not compile (#2921).
- **An element store into an owning array local takes its value.**
  `xs[0] = f` on a `fn[N]` or tuple array local leaked what the element held
  (#2921).
- **A `string?`, tuple or struct message field takes its value.** A send
  shared the sender's string with the message, and the receiver's release
  freed it under the sender (#2922).
