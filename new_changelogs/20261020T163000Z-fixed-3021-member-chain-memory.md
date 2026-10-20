- **Type checking a chain of field reads is linear again.** `infer_type`
  inferred a member access's object once per check it made (`.len`, lanes,
  bitstructs, the field lookup), each of which re-inferred the whole chain
  under it, and leaked the object's type whenever the field was found. A
  chain through pointers, `n.next.next ... .v`, took about 4x more memory
  per link: 1.7 GB at 14 links, and a 150-link chain exhausted a 32 GB
  machine. The object is now inferred once per access and freed once; 99
  links check in a fraction of a second (#3021).
