- **A string read out of a `string[]` slice is copied where it escapes.**
  A function returning `xs[0]` of a slice handed the string back borrowed
  from whatever the slice viewed, and the caller held it after its owner
  let go of it: an array that owns its elements freed it on the next store
  or at its exit. A slice owns none of its elements, so a slot its element
  escapes to now takes a copy of its own, as for an element of an owning
  array (#2618): a return (directly, in an `if` or `match` arm, as a tuple
  position), a struct field, a container, or a call that hands its
  argument back. A local bound to a slice element (`t = s[i]`) still
  borrows it, so moving elements through a local
  (`t = s[0]; s[0] = s[1]; s[1] = t`) moves the pointers and keeps none,
  and the local is valid only while the element is; returned or added to
  a container, the local is copied in turn. A store into a slice element
  frees nothing and hands the storage what it stores, so moving an element
  through a copy (a function returning `s[i]`, stored back over another
  element) leaks the element it replaces; move elements through a local
  (#2689).
