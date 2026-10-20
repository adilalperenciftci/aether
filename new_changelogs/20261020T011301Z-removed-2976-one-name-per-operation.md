- **A module exports one name per operation.** **Breaking:** two exports
  that answer to one short name, a wrapper `add` beside its extern
  `aether_set_add` or `free` beside `tally_free`, are now error E0305,
  naming both (a module with no `exports(...)` list is held to it over its
  top-level declarations). `m.add` reached one and `m.aether_m_add` the
  other: the same operation twice, or a different one that read as the same
  (std.set's extern returned 1 where its wrapper returns `true`). std's
  export lists drop 336 such names; each operation is reached by its short
  name, `set.add` for `set.aether_set_add`, `mem.get_byte` for
  `mem.aether_mem_get_byte`, `string.join` for `string.string_join`, and
  where the wrapper's name differs: `set.contains` (`aether_set_has`),
  `set.items` (`aether_set_items_raw`), `audit.entry` (the three
  `aether_audit_entry_*`), `bytes.copy_from_slice`
  (`aether_bytes_copy_from_ptr`), `casper.service`, `casper.dns_resolve`,
  `casper.sysctl` (`aether_casper_service_open`, `_resolve`,
  `_sysctl_str`), `config.put`/`get`/`get_or`/`has`/`size`/`clear` (the
  `aether_config_store_*`), `mem.set` (`aether_mem_set_bulk`),
  `regex.capture_count`/`capture`/`capture_start`/`capture_end` (the
  `aether_regex_captures_*`), `strbuilder.append_slice`
  (`aether_strbuilder_append_bytes`), `string.bytes`
  (`aether_string_raw_ptr`), `string.from_ptr` (`aether_string_is_string`),
  `worker.pool_size` (`aether_worker_pool_configure`), `os.memory_resident`
  and `os.memory_private` (`aether_process_*`). `intmap.add` panics on out
  of memory, so `aether_intmap_add_failed` has no counterpart. A program
  calling a removed name gets E0303 and calls the short name instead; a C
  host still links the C functions, which are unchanged. contrib's bridges
  follow the same rule: `perl.run` and the rest, not their C names (#2976).
  Removed:
  - contrib.host.perl (5): `aether_perl_finalize`, `aether_perl_init`, `aether_perl_run`, `aether_perl_run_sandboxed`, `aether_perl_run_sandboxed_with_map` (call `perl.finalize`, `perl.init`, `perl.run`, `perl.run_sandboxed`, `perl.run_sandboxed_with_map`)
  - std.actors (6): `aether_actor_is_registered`, `aether_actor_register`, `aether_actor_registry_clear`, `aether_actor_registry_size`, `aether_actor_unregister`, `aether_actor_whereis`
  - std.arena (5): `arena_alloc`, `arena_alloc_aligned`, `arena_create`, `arena_destroy`, `arena_reset`
  - std.audit (5): `aether_audit_clear`, `aether_audit_count`, `aether_audit_entry_allowed`, `aether_audit_entry_category`, `aether_audit_entry_resource`
  - std.bits (17): `aether_bits_clz32`, `aether_bits_clz64`, `aether_bits_lsr32`, `aether_bits_lsr64`, `aether_bits_popcount32`, `aether_bits_popcount64`, `aether_bits_rotl32`, `aether_bits_rotl64`, `aether_bits_rotr32`, `aether_bits_rotr64`, `aether_bits_ucmp64`, `aether_bits_udiv32`, `aether_bits_udiv64`, `aether_bits_urem32`, `aether_bits_urem64`, `aether_bits_wrapping_add64`, `aether_bits_wrapping_mul64`
  - std.bytes (26): `aether_bytes_capacity`, `aether_bytes_copy_from_bytes`, `aether_bytes_copy_from_ptr`, `aether_bytes_copy_from_string`, `aether_bytes_copy_within`, `aether_bytes_data`, `aether_bytes_finish`, `aether_bytes_free`, `aether_bytes_get`, `aether_bytes_get_be16`, `aether_bytes_get_be32`, `aether_bytes_get_be64`, `aether_bytes_get_le16`, `aether_bytes_get_le32`, `aether_bytes_get_le64`, `aether_bytes_length`, `aether_bytes_new`, `aether_bytes_set`, `aether_bytes_set_be16`, `aether_bytes_set_be32`, `aether_bytes_set_be64`, `aether_bytes_set_le16`, `aether_bytes_set_le32`, `aether_bytes_set_le64`, `aether_bytes_set_length`, `aether_bytes_to_string`
  - std.capsicum (5): `aether_capsicum_available`, `aether_capsicum_enter`, `aether_capsicum_fcntls_limit`, `aether_capsicum_in_mode`, `aether_capsicum_rights_limit`
  - std.casper (8): `aether_casper_available`, `aether_casper_close`, `aether_casper_init`, `aether_casper_pwd_home`, `aether_casper_pwd_uid`, `aether_casper_resolve`, `aether_casper_service_open`, `aether_casper_sysctl_str`
  - std.config (6): `aether_config_store_clear`, `aether_config_store_get`, `aether_config_store_get_or`, `aether_config_store_has`, `aether_config_store_put`, `aether_config_store_size`
  - std.floatarr (1): `floatarr_array`
  - std.fs (1): `fs_last_os_error`
  - std.host (3): `aether_caller_attribute`, `aether_caller_deadline_ms`, `aether_caller_identity`
  - std.http (32): `http_request_body`, `http_request_body_complete`, `http_request_body_length`, `http_request_header_count`, `http_request_header_name`, `http_request_header_value`, `http_request_http_version`, `http_request_is_tls`, `http_request_local_addr`, `http_request_local_port`, `http_request_method`, `http_request_path`, `http_request_query`, `http_request_remote_addr`, `http_request_remote_port`, `http_request_scheme`, `http_response_accept_tunnel`, `http_serve_file`, `http_serve_static`, `http_server_set_host`, `http_server_sse`, `http_server_websocket`, `http_sse_close`, `http_ws_client_free`, `http_ws_close`, `http_ws_connect`, `http_ws_fd`, `http_ws_poll`, `http_ws_recv`, `http_ws_recv_timeout`, `http_ws_send_binary`, `http_ws_send_text`
  - std.intarr (1): `intarr_array`
  - std.intmap (13): `aether_intmap_add`, `aether_intmap_add_failed`, `aether_intmap_clear`, `aether_intmap_free`, `aether_intmap_get`, `aether_intmap_has`, `aether_intmap_key_at`, `aether_intmap_new`, `aether_intmap_next`, `aether_intmap_put`, `aether_intmap_remove`, `aether_intmap_size`, `aether_intmap_value_at`
  - std.longarr (1): `longarr_array`
  - std.lzf (1): `lzf_max_compressed_size`
  - std.mem (82): `aether_heap_in_use`, `aether_heap_in_use_exact`, `aether_mem_bits_of_float`, `aether_mem_call_fn2_void`, `aether_mem_call_fn3_int`, `aether_mem_call_fn3_void`, `aether_mem_clz32`, `aether_mem_clz64`, `aether_mem_compare`, `aether_mem_compare_at`, `aether_mem_copy`, `aether_mem_copy_at`, `aether_mem_fill_at`, `aether_mem_float_from_bits`, `aether_mem_get_byte`, `aether_mem_get_byte_sz`, `aether_mem_get_byte_sz_unchecked`, `aether_mem_get_byte_unchecked`, `aether_mem_get_float32`, `aether_mem_get_float32_unchecked`, `aether_mem_get_float64`, `aether_mem_get_float64_unchecked`, `aether_mem_get_int`, `aether_mem_get_int16`, `aether_mem_get_int16_unchecked`, `aether_mem_get_int8`, `aether_mem_get_int8_unchecked`, `aether_mem_get_int_unchecked`, `aether_mem_get_long`, `aether_mem_get_long_unchecked`, `aether_mem_get_ptr`, `aether_mem_get_ptr_unchecked`, `aether_mem_get_u16_be`, `aether_mem_get_u16_le`, `aether_mem_get_u32_be`, `aether_mem_get_u32_le`, `aether_mem_get_u64_be`, `aether_mem_get_u64_le`, `aether_mem_get_uint16`, `aether_mem_get_uint16_unchecked`, `aether_mem_get_uint32`, `aether_mem_get_uint32_unchecked`, `aether_mem_get_uint8`, `aether_mem_get_uint8_unchecked`, `aether_mem_long_to_ptr`, `aether_mem_move`, `aether_mem_move_at`, `aether_mem_ptr_to_long`, `aether_mem_set_bulk`, `aether_mem_set_byte`, `aether_mem_set_byte_sz`, `aether_mem_set_byte_sz_unchecked`, `aether_mem_set_byte_unchecked`, `aether_mem_set_float32`, `aether_mem_set_float32_unchecked`, `aether_mem_set_float64`, `aether_mem_set_float64_unchecked`, `aether_mem_set_int`, `aether_mem_set_int16`, `aether_mem_set_int16_unchecked`, `aether_mem_set_int8`, `aether_mem_set_int8_unchecked`, `aether_mem_set_int_unchecked`, `aether_mem_set_long`, `aether_mem_set_long_unchecked`, `aether_mem_set_ptr`, `aether_mem_set_ptr_unchecked`, `aether_mem_set_u16_be`, `aether_mem_set_u16_le`, `aether_mem_set_u32_be`, `aether_mem_set_u32_le`, `aether_mem_set_u64_be`, `aether_mem_set_u64_le`, `aether_mem_set_uint16`, `aether_mem_set_uint16_unchecked`, `aether_mem_set_uint32`, `aether_mem_set_uint32_unchecked`, `aether_mem_set_uint8`, `aether_mem_set_uint8_unchecked`, `aether_mem_swap_ptrs`, `aether_mem_udiv64_32`, `aether_thread_epoch`
  - std.observe (8): `aether_observe`, `aether_observe_fields`, `aether_observe_is_notifying`, `aether_observe_notify`, `aether_observe_notify_field`, `aether_observer_count`, `aether_unobserve`, `aether_unobserve_all`
  - std.os (2): `aether_process_private`, `aether_process_resident`
  - std.path (9): `path_basename`, `path_clean`, `path_dirname`, `path_extension`, `path_is_absolute`, `path_is_within_base`, `path_join`, `path_rel`, `path_separator`
  - std.pqueue (9): `aether_pqueue_clear`, `aether_pqueue_free`, `aether_pqueue_is_empty`, `aether_pqueue_new`, `aether_pqueue_peek`, `aether_pqueue_peek_priority`, `aether_pqueue_pop`, `aether_pqueue_push`, `aether_pqueue_size`
  - std.reflect (20): `aether_schema_attr_arg_count`, `aether_schema_attr_arg_kind`, `aether_schema_attr_count`, `aether_schema_attr_float`, `aether_schema_attr_index`, `aether_schema_attr_int`, `aether_schema_attr_name`, `aether_schema_attr_text`, `aether_schema_field_count`, `aether_schema_field_elem_kind`, `aether_schema_field_index`, `aether_schema_field_kind`, `aether_schema_field_len`, `aether_schema_field_name`, `aether_schema_field_offset`, `aether_schema_field_schema`, `aether_schema_field_size`, `aether_schema_field_type`, `aether_schema_name`, `aether_schema_size`
  - std.regex (18): `aether_regex_captures`, `aether_regex_captures_count`, `aether_regex_captures_end`, `aether_regex_captures_free`, `aether_regex_captures_get`, `aether_regex_captures_start`, `aether_regex_clear_last_error`, `aether_regex_compile`, `aether_regex_find_all`, `aether_regex_find_all_count`, `aether_regex_find_all_end`, `aether_regex_find_all_free`, `aether_regex_find_all_start`, `aether_regex_free`, `aether_regex_last_error`, `aether_regex_matches`, `aether_regex_replace`, `aether_regex_replace_all`
  - std.set (9): `aether_set_add`, `aether_set_clear`, `aether_set_free`, `aether_set_has`, `aether_set_items_free`, `aether_set_items_raw`, `aether_set_new`, `aether_set_remove`, `aether_set_size`
  - std.snapshot (5): `aether_snapshot_cas`, `aether_snapshot_free`, `aether_snapshot_load`, `aether_snapshot_new`, `aether_snapshot_store`
  - std.strarr (2): `strarr_free`, `strarr_size`
  - std.strbuilder (17): `aether_strbuilder_append`, `aether_strbuilder_append_byte`, `aether_strbuilder_append_bytes`, `aether_strbuilder_append_codepoint`, `aether_strbuilder_append_hex`, `aether_strbuilder_append_int`, `aether_strbuilder_append_long`, `aether_strbuilder_append_n`, `aether_strbuilder_capacity`, `aether_strbuilder_clear`, `aether_strbuilder_finish`, `aether_strbuilder_finish_with_length`, `aether_strbuilder_free`, `aether_strbuilder_length`, `aether_strbuilder_new`, `aether_strbuilder_reserve`, `aether_strbuilder_truncate`
  - std.string (3): `aether_string_is_string`, `aether_string_raw_ptr`, `string_join`
  - std.sync (7): `aether_sync_atomic_add`, `aether_sync_atomic_cas`, `aether_sync_atomic_free`, `aether_sync_atomic_load`, `aether_sync_atomic_new`, `aether_sync_atomic_store`, `aether_sync_atomic_sub`
  - std.udp (3): `udp_addr_free`, `udp_addr_new`, `udp_close`
  - std.worker (9): `aether_worker_deliver`, `aether_worker_drain`, `aether_worker_pending`, `aether_worker_pool_configure`, `aether_worker_pool_shutdown`, `aether_worker_run`, `aether_worker_run_detached`, `aether_worker_set_main_poster`, `aether_worker_wait`
  - std.xml (2): `xml_escape`, `xml_next`
