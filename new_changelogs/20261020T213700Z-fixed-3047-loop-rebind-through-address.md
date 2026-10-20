- **E0902's check of a loop's next pass reads a local through its address
  as by name.** A field the loop's body binds anew, read back through the
  struct's address (`pb = (&b) as *Box`, `kept = pb.item`) after the
  store, holds what the pass stored, as it does read by name; read through
  the address before the store, it still carries the pass before's value
  (#3047).
