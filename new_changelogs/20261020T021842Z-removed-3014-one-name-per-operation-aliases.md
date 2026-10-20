- **std exports one name for each operation it aliased.** **Breaking:**
  some modules exported an operation under two names whose short forms
  differ, an Aether alias beside the extern or function it forwards to,
  which E0305 (one short name, #2976) cannot see: `json.from_int` beside
  `json.create_int`, `xml.writer` beside `xml.builder_new`. The Aether-side
  name stays (std.cbor's `map_push`, which appends a pair, over `map_set`);
  the other leaves the export list, and calling it is E0303. Removed, with
  the name to call instead (#3014):
  - std.json (10): `create_object` (`obj`), `create_array` (`arr`), `create_string` (`str`), `create_number` (`num`), `create_int` (`from_int`), `create_bool` (`boolean`), `create_null` (`null_value`), `object_set` (`set`), `array_add` (`push`), `stringify` (`encode`)
  - std.cbor (4): `object_set` (`set`), `array_add` (`push`), `map_set` (`map_push`), `stringify` (`encode`)
  - std.xml (18): `parser_new_str` (`parser`), `event_name` (`name`), `event_text` (`text`), `event_attr_count` (`attr_count`), `event_attr_name` (`attr_name`), `event_attr_value` (`attr_value`), `event_attr_str` (`attr`), `parser_error` (`error`), `parser_free` (`free`), `builder_new` (`writer`), `builder_declaration` (`declaration`), `builder_start` (`start`), `builder_attr` (`attribute`), `builder_text` (`text_node`), `builder_end` (`end`), `builder_element` (`element`), `builder_finish` (`finish`), `builder_free` (`free_builder`), each also as `xml_<name>`
  - std.bytes.cursor (17): every `bytes_cursor_<x>` (`cursor.<x>`), and `bytes_cursor_new_from_ptr` (`cursor.from_slice`)
  - std.arena (2): `get_size` (`size`), `get_used` (`used`)
  - std.fs (8): `path_exists` (`exists`), `path_clean` (`clean`), `path_rel` (`rel`), `path_is_within_base` (`is_within_base`), `get_mount_point`, `get_mount_source`, `get_mount_fstype`, `get_mount_options` (`mount_point`, `mount_source`, `mount_fstype`, `mount_options`)
  - std.http (7): `server_set_on_start` (`server_on_start`), `server_set_on_stop` (`server_on_stop`), `sse_send_event` (`sse_send`), `sse_send_event_id` (`sse_send_id`), `sse_send_event_full` (`sse_send_full`), `ws_message_data` (`ws_message`), `ae_io_await` (`await_io`)
  - std.net (5): `ae_io_await` (`await_io`), `ae_pipe_open` (`pipe_open`), `ae_pipe_write_fd` (`pipe_write_fd`), `ae_fd_write` (`fd_write`), `ae_fd_close` (`fd_close`)
  - std.brotli, std.zlib, std.zstd (1 each): `backend_available` (`available`)
  - std.os (5): `aether_args_count` (`os.args_count`), `aether_args_get` (`os.args_get`, an owned copy, `""` out of range), `aether_argv0` (`os.argv0`, `""` before argv is set), `aether_args_seal` (`os.args_seal`), `aether_args_sealed` (`os.args_sealed`); a bare `aether_args_count()` reached the export too. `os.aether_argv_raw` has no wrapper and stays.
