- **A `string?` a function returns is its caller's own.** The caller of a
  function returning `string?` frees the string in the result, whatever the
  function returned, so a borrowed parameter, a literal, or an element of
  an array or a slice returned as it was got freed by the caller (heap
  corruption). Every return now hands over a string of its own, as a
  `-> string` return does: a fresh one, or a local's own, as it is, and
  anything borrowed copied; an optional passed on is kept when it comes
  from a call or from a `string?` local that owns its string, and copied
  otherwise. Such a return no longer keeps the argument it copies, so the
  caller frees its argument as usual (#2740).
