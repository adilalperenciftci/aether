- **An owned type whose drop returns a value or has a typed C prototype
  compiles again.** The checker takes any one-parameter `@frees ptr`
  function as an owned type's drop, whatever it returns. The unwind journal
  entry of an owned place (#3406) passed the drop itself where a `void`
  function of a `void*` was expected, so a drop such as `rel(p: @frees ptr)
  -> int`, or C's `fclose` (`int fclose(FILE*)`), failed to compile with
  "incompatible pointer type", in a local and in an arm's binding alike. The
  journal now holds a thunk per drop function, which calls the drop as the
  scope's exit does (#3413).
