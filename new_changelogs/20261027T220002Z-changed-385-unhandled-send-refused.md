- **A send no arm of the target actor takes is a compile error.** `w !
  Close {}` and `w ? Close {}` only checked that `w` was an actor reference
  and `Close` a declared message, so a message the actor had no receive arm
  for compiled and was dropped at run time. Where the target's type names
  its actor (a `spawn(Writer())` result, a reference typed
  `actor_ref[Writer]`, an actor from an imported module) such a send is now
  refused (E0600), naming the actor and the message; a `_` arm takes every
  message, and a bare `actor_ref` is not checked (#385).
