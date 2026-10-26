- **An ask has its reply's type wherever it stands, and its reply is
  reclaimed.** Only a binding inferred an ask's type, so one given straight
  to a function, into an interpolation or to `println` was an `int`, and a
  string reply printed as a number (`println(e ? Label {})`). It now has its
  reply's type in every position, its message checked as a send's is, and
  the reply string an unbound ask hands over is released after the
  expression that reads it, as a call's result is. Argument temporaries are
  now read back by node whatever its kind, so no argument is evaluated twice
  (#3165).
