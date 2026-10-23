- **`.len` is an array's only member, and any other name says so.**
  `arr.length` passed the checker and stopped at the C compiler ("request
  for member 'length' in something not a structure or union"), and so did
  `a.size` on a fixed-size array or `.length` on an array of closures. On
  a slice or an array, a member other than `.len` is now a type error that
  names `.len` (#3092).
