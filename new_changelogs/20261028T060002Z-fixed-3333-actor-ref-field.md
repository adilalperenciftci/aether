- **A field access through a bare `actor_ref` is a type error.** It passed
  the checker and failed in the C compiler (a bare reference is a `void*`
  and names no actor). The checker refuses it with a hint to type the
  reference (`actor_ref[Counter]`), and refuses a typed reference naming a
  state its actor does not have, which reached C the same way (#3333).
