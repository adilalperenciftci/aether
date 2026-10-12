- **A closure frees its `string?` and `*StringSeq` locals.** A closure body
  ran the heap-string passes a function body runs but not their `string?`
  and `*StringSeq` counterparts, so such a local was declared with no
  ownership flag and no exit free, and every call of the closure leaked
  what it held. The closure body now runs all of them, as a function body
  does (#2761).
