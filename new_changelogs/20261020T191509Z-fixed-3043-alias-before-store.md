- **E0902 sees a borrowed `ptr` stored after a local's address was taken.**
  `ps = (&s) as *Pair`, then `s.a = p`, then `kept = ps.a` kept the
  borrowed parameter `p` with no error: a pointer to a local carried what
  the local held when the address was taken. It now reads the local as it
  is when read, through copies of the address (`qs = ps`) and an address
  of a field (`&o.inner`, which reads that field) (#3043).
