- **A message's strings cross to the receiving actor's thread safely.** A
  field that shares a counted string with its sender (a tuple, a struct, an
  optional or an array that owns strings) took it with a plain increment,
  and nothing published it, so the receiver's release raced the sender's
  next take on a non-atomic count and the sender's last release freed the
  string twice (the ownership grid's `K6-P12D-T12`, a double free on
  Windows). Such a field is published at the send, the ask and the reply
  (#3192). On the C path without statement expressions (what MSVC
  compiles), an ask's string fields are the message's own copies, as on
  the GCC path: the receiver's release freed the sender's string (#3193).
