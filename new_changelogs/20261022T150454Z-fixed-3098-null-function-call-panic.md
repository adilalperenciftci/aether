- **A call through a null function pointer is a named panic.** A typed
  function pointer (`fn(int) -> int`, a `cfn` type) holding `null`, called
  from a local, a parameter, a field, a module-level `var`, an array
  element or a function's result, jumped to address 0 and crashed with no
  message. The call now panics with the category `null_function_call` and
  its source position, which a `catch` receives (#3098). A typed function
  pointer reached through an element or a field of a field (`fs[1](x)`,
  `w.h.cb(x)`) is called through its signature, not as a closure.
