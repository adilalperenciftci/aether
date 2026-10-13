- **A struct can hold an optional field.** `struct Box { v: int? }` named
  `ae_opt_int` before its typedef, which came after every struct body, and
  `Box { v: 7 }` or `b.v = none` gave the field a bare value, so gcc
  rejected the program. The typedef a struct needs is declared ahead of
  it (an optional of a struct after that struct's body), and a literal or
  a field store wraps a bare value as an optional binding does. An
  optional field whose value owns memory (`string?`, an optional `fn`, an
  optional of a struct holding a string) is refused with a diagnostic
  until it has a `string` field's ownership (#2820, #2822).
