- **`actor_ref[8]` is an array of eight actor references.** The size was
  read as actor_ref's type parameter, so `state members: actor_ref[8]`
  and `actor_ref[MAX]` were parse errors at the size. A number, a `(` or
  a `const` of the file after `actor_ref[` starts the array; any other
  name is still the actor type (`actor_ref[Member][8]`) (#3189).
