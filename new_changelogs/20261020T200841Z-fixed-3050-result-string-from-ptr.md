- **A `string!` function may return a `ptr` as its string.** `return p`
  with `p` a `ptr` parameter is accepted in a `-> string` function, which
  hands the caller a reference of its own, but in a `-> string!` function it
  was E0902 ("a borrowed `ptr` parameter, returned"), though the generated
  C makes the same reference. The one value a `T!` function returns is now
  checked as its `T` there too (#3050).
