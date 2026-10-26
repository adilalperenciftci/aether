- **The std.http.middleware factories no longer leak their options.** Each
  factory (`use_cors`, `use_basic_auth`, `use_bearer_auth`,
  `use_session_auth`, `use_rate_limit`, `use_vhost`, `use_gzip`,
  `use_static_files`, `use_rewrite`, `use_error_pages`, `use_real_ip`)
  registered an options block that `http.server_free` never released: from
  8 bytes (gzip) to about 2 KB (the rate limiter's table) per server. Each
  now hands the block to the server with its own free, and response
  transformers gained the release hook middleware got in #3171
  (`http_server_use_response_transformer_owned`). The opts passed to
  `use_rewrite` and `use_error_pages` belong to the server from then on
  (#3191).
