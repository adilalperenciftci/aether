- **Mutually recursive functions with inferred results keep their type.**
  `a` returning `p.n` (a long read through a pointer) or `b(...)`, and `b`
  returning `a(...)`, gave `b` the int default, so a long that went through
  it was cut to 32 bits (705032704 for 5000000000, as in 0.836.0). The
  functions of such a cycle are checked in an order that types each from
  the one whose `return` gives the type, whichever the program reaches
  first (#3056).
