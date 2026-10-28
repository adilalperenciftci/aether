- **A function can take or return `actor_ref[Actor]`.** Its C declaration
  names the actor's type, and the function declarations came before the
  actors' forward typedefs, so the C compile failed with "unknown type
  name". Actor typedefs are now declared with the structs', ahead of every
  function (#3290).
