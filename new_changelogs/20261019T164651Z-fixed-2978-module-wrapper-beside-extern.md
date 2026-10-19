- **A module function named like one of its module's externs is kept.**
  The merge dropped a module function whose C name `<ns>_<name>` was one of
  the module's own externs, and `ns.name(...)` called the extern. Std had 64
  such pairs, and four wrappers did more than forward:
  `http.server_set_host(s, host)` returns `""` where the extern returns
  nothing (`err = http.server_set_host(...)` failed in C),
  `http.ws_send_binary(ws, data)` takes a `byte[]` where the extern takes a
  pointer and a length (the documented call was "expects 3 argument(s)"),
  `xml.escape` copies the extern's result, and `string.join` joins with
  `string_seq_join`. Such a function is merged as `ae_<ns>_<name>` now, a
  bare call in its module, a qualified `ns.name` and an import of the name
  reach it, and its own call of the extern still reaches the extern
  (#2978).
