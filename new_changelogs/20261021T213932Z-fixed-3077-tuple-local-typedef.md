- **A tuple local that owns nothing compiles.** `t = (null, 1)`, `(p, 1)`
  with p a `ptr`, and `(1.5, true)`, bound to a local and destructured,
  failed in the C compiler with "unknown type name '_tuple_ptr_int'": the
  tuple's C type was declared after the line that used it. Every tuple
  type a program uses is declared ahead of its functions now (#3077).
