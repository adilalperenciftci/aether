- **Any expression whose value is a function can be called.** `fs[1]()` was
  refused as "Undefined function '?'": the parser kept only a name, a
  `module.fn` or a field as a callee and dropped any other. An element, a
  call's result (`make_adder(5)(2)`) and a closure field of a receiver that
  is not a name (`hs[0].cb()`) are now called as a closure local is,
  through `call(callee, args)`. The callee is evaluated once and held for
  its call, and one whose value is not a function is refused as such (#3099).
