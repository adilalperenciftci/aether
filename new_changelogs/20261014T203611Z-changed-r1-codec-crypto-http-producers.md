- **The codec, crypto and network producers hand over counted strings.**
  `json_stringify_raw`, `xml_builder_finish`, `xml_escape`, the two base64
  encoders, the seven `*_hex_raw` digests, `tcp_receive_raw`,
  `aether_proxy_pool_metrics_text` and the two Windows trust-anchor helpers
  returned a plain malloc'd `char*`; each now returns a fresh AetherString
  the caller releases with `string_release`, adopting its buffer where it
  was already cap-accounted, so every `string` they produce is counted as
  the ownership model's R1 asks. Their declarations, and the `string_concat`
  and `string_substring` redeclarations in std.json, std.xml, std.yaml,
  std.http, std.http.client and std.http.middleware, say `@heap`. Without
  networking, `http_response_body` and `http_response_read_chunk_raw`
  returned a literal `""` under `@heap`, which the caller's release then
  freed; they return an empty counted string now. `tcp_receive_raw`'s
  result keeps the length received instead of stopping at a NUL.
