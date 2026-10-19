- **A list pattern in a match arm binds its elements with their type.**
  Every name a match arm's list pattern bound was an `int` read through an
  `int*`, so a match over a `float[]`, a `string[]` or a struct array did not
  compile. They take the element type of the value matched, as the checker
  types them. A string element the arm re-binds takes a reference of its own,
  which the arm releases; a re-bound head leaked that reference, over a
  `*StringSeq` as well (#2997).
