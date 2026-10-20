- **E0902 checks a `defer` where it runs.** A `defer` reads what its
  block's locals hold when the block is left, but its statement was
  checked where it is written, so `q = list.new()`, `defer kept = q`,
  `q = p` stored the borrowed `p` unrefused. A defer is now checked at the
  end of its block, and in a loop's body at the end of each pass (#3057).
