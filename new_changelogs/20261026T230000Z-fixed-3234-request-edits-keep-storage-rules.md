- **`use_real_ip` and `use_rewrite` edit a request the way it is stored.**
  Adding X-Real-IP grew the request's header arrays to one past the headers
  they held, which shrank them, so a request object parsed into again wrote
  up to 50 headers into a handful of slots; and replacing X-Real-IP or the
  path called `free()` on strings that a request parsed into an arena keeps
  in the arena. Both go through new request edits in std.net
  (`http_request_set_header`, `http_request_remove_header`,
  `http_request_set_path`), which grow the arrays and never shrink them, and
  move an arena-backed request's strings out of the arena before replacing
  one. `HttpRequest` records its arrays' size in a new trailing field,
  `header_cap` (#3234).
