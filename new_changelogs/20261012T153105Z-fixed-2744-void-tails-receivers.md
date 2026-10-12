- **Whether a function returns a value is settled right for a tail called
  on a receiver or through a parameter.** The settle that decides, before any
  body is checked, which functions return a value (#2736) resolved the calls
  in their returns by name, so a tail whose callee depends on what it is
  called on was taken to give a value: a UFCS call (`b.show()`,
  `mk(n).show()`), a call through a function-pointer field (`o.run(n)`) and a
  call through a parameter typed `fn(int)` (`f(x)`). The function was emitted
  as returning nothing while its caller returned its value, and the C
  compiler stopped ("void value not ignored"), in either definition order.
  The settle now runs after inference and resolves those calls as the
  checker does, with the receiver's type. Also, `call(f, x)` through a typed
  function pointer is the call `f(x)`, where it was emitted as a closure call
  that C refused (#2744).
