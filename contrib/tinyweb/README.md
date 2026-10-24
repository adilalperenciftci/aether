# TinyWeb for Aether

A DSL-style HTTP server library. Port of [Tiny](https://github.com/phamm/tiny).

## Usage

```aether
server = web_server_host("localhost", 8080) {

    path("/foo") {
        filter(GET, "/.*") |req, res, ctx| {
            return CONTINUE
        }
        end_point(GET, "/bar") |req, res, ctx| {
            response_write(res, "Hello, World!")
        }
        web_socket("/eee") |msg, sender, ctx| {
            http.ws_send_text(sender, "Echo: ${msg}")
        }
    }

    serve_static("/static", ".")

    end_point(GET, "/users/(\\w+)") |req, res, ctx| {
        response_write(res, "User: ${request_get_path_param(ctx, \"1\")}")
    }
}
err = tw_start(server)
```

## Features

- **HTTP endpoints**: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, and 18 extended methods
- **Path nesting**: `path("/api") { path("/v1") { end_point(...) } }`
- **Filters**: `filter(GET, "/.*") |req, res, ctx| { CONTINUE / STOP }`
- **Composition**: `compose(server) { ... }` to add routes after construction
- **WebSocket**: `web_socket("/ws") |msg, sender, ctx| { ... }`, on the
  server's own port
- **SSE**: `sse_endpoint("/events") |stream| { sse_send(stream, data) }`
- **Static files**: MIME detection, traversal protection, index.html fallback
- **Chunked transfer**: `chunked_start`, `write_chunk`, `chunked_end`
- **Cookies**: `request_get_cookie(req, "name")`
- **Attributes**: `ctx_set_attribute` / `ctx_get_attribute` for filter-to-endpoint data
- **Statistics**: `on_stats(server) |stats| { ... }`
- **Config**: `with_timeout`, `with_keep_alive`, `with_tls`

### WebSocket, SSE and chunked responses

All three are std.http's, served on the same port as the HTTP routes, TLS
included:

- A `web_socket` handler runs once per message. `msg` is the whole message,
  of any length, a binary one zero bytes and all; `sender` is the
  connection's std.http WebSocket (reply with `http.ws_send_text` or
  `http.ws_send_binary`); `ctx` is a map the connection's messages share.
  Pings are answered, and a quiet connection stays open.
- An `sse_endpoint` handler gets the stream and runs until it returns.
  `sse_send`, `sse_send_event` and `sse_comment` return 0, or -1 once the
  client has gone, so a handler that streams in a loop knows when to stop.
- An endpoint streams a body of unknown length with
  `stream, err = chunked_start(res, status)`, `write_chunk(stream, data)`
  and `chunked_end(stream)`. The headers set on `res` before it go out with
  it; a response that already has a body is refused.

### Statistics

`on_stats(server) |stats| { ... }` runs after each request to an
`end_point` with a record of it: `stats_get_path`, `stats_get_endpoint` (the
route's pattern), `stats_get_status`, `stats_get_duration` and
`stats_get_endpoint_duration` (milliseconds), and `stats_get_filters`, a
list of the filters that ran (`filter_stat_path`, `filter_stat_result`,
"CONTINUE" or "STOP", and `filter_stat_duration`).

### Timeouts and keep-alive

`with_timeout(server, ms)` is how long a connection may wait for its next
request (30000 by default); an upgraded WebSocket or an SSE stream is not
held to it. `with_keep_alive(server, 0)` closes each connection after its
response.

### IPv6

`web_server_host` takes an IPv6 address as well as a name or an IPv4 one.
`"::"` listens on every interface of both families, which is what an
IPv6-only host (or one that wants both) needs; IPv4 clients arrive on it and
`request_remote_addr` reports them as plain IPv4 (`203.0.113.7`). `"::1"` is
IPv6 loopback alone, and `"localhost"` still means 127.0.0.1.

```aether
server = tinyweb.web_server_host("::", 8443) {
    tinyweb.end_point(tinyweb.GET, "/") |req: ptr, res: ptr, ctx: ptr| {
        tinyweb.response_write(res, "hello over either family")
    }
}
```

### TLS

```aether
server = tinyweb.web_server_host("0.0.0.0", 443) {
    tinyweb.end_point(tinyweb.GET, "/") |req: ptr, res: ptr, ctx: ptr| {
        tinyweb.response_write(res, "hello over https")
    }
}
_ = tinyweb.with_tls(server, "/etc/ssl/cert.pem", "/etc/ssl/key.pem")
err = tinyweb.tw_start(server)
```

Both paths are PEM. `tw_start` applies them before registering routes, so a
missing file or a malformed pair is a **start-up error** rather than a server
that quietly serves plaintext on a port callers believe is encrypted: passing
a cert without a key is refused for the same reason.
- **Declarative JSON APIs** (`schema_api`): mount a [`std.schema`](../../std/schema/)
  resource as a validated JSON API; see below.

## Declarative JSON APIs: `schema_api` + `std.schema`

`contrib/tinyweb/schema_api` bridges [`std.schema`](../../std/schema/) (typed,
composable validation: inspired by Zod/Pydantic/io-ts/Ash) to the router. You
declare a resource once and mount it; every write request is JSON-parsed and
validated **before** your handler runs. Invalid bodies never reach the handler:
they get a JSON:API `422` with per-field, coded errors; malformed JSON a `400`.

```aether
user = schema.record() {
    schema.field("name",  schema.STR)   { schema.trim(); schema.present(); schema.len(1, 60) }
    schema.field("email", schema.STR)   { schema.trim(); schema.lowercase(); schema.email() }
    schema.field("age",   schema.INT)   { schema.positive(); schema.max(120) }
    schema.field("role",  schema.STR)   { schema.one_of("admin,user"); schema.default_to("user") }
    schema.field("score", schema.FLOAT) { schema.min(0) }
}

registry = list.new()
server = tinyweb.web_server_host("127.0.0.1", 8080) {
    u = schema_api.json_api("/users", user) {
        schema_api.create() |req, res, ctx| {
            // body already parsed, coerced, and normalized: handle it
            tinyweb.response_write_status(res, "{\"ok\":true}", 201)
        }
    }
    list.add(registry, u)
    schema_api.openapi_route("/openapi.json", registry)   // FastAPI-style aggregate
}
```

Every mounted resource **projects itself**, not just gates requests:

- `GET {prefix}/schema`: auto-serves the resource's **draft-07 JSON Schema**
  (`std.schema.to_json_schema`): `enum`, `format:email`, `minimum`/`maximum`,
  `default`, `required`, …
- `GET /openapi.json` (via `openapi_route`): an aggregate **OpenAPI 3.0**
  document for every resource: `paths` + `components.schemas`, `$ref`-linked.

The validator is HTTP-agnostic: the same `record` validates a config file or a
CLI arg set off the web entirely. Runnable demo: `example_schema_api.ae`. The
JSON:API error envelopes and the schema/OpenAPI docs are built with `strbuilder`
(leak-clean; avoids the `std.json` builder-nesting leak, upstream #1447).

## DSL semantics

Each DSL call falls into one of two categories: **container** (its trailing
block runs once at registration time and may contain more DSL calls) or
**leaf** (its trailing block, if any, is stored as a request-time handler).

| Call            | Trailing block runs…  | What gets stored             | Can nest DSL inside? |
|-----------------|-----------------------|------------------------------|----------------------|
| `web_server`    | now (once, root)      | nothing                      | yes: root container |
| `path`          | now (once)            | nothing (block populates parent | yes) `path`, `end_point`, `filter`, `web_socket`, `sse_endpoint`, `serve_static` |
| `end_point`     | later (per request)   | the block, as a handler      | leaf only            |
| `filter`        | later (per request)   | the block, as a handler      | leaf only            |
| `web_socket`    | later (per message)   | the block, as a handler      | leaf only            |
| `sse_endpoint`  | later (per stream)    | the block, as a handler      | leaf only            |
| `serve_static`  | n/a (no block)        | base→dir mapping             | leaf only            |

Only `web_server` and `path` are nesting containers. Everything else is a
leaf: its block, if any, is a request-time handler, not more DSL.

## Files

- `module.ae`: The library
- `example_app.ae`: HTTP endpoints with filters and nested paths
- `example_composition.ae`: Modular composition, deep nesting, auth filters
- `example_websocket.ae`: HTTP + WebSocket routes with echo handlers
- `example_static.ae`: Static file serving
- `example_sse.ae`: Server-Sent Events + chunked transfer
- `example_auth.ae`: Cookie parsing + filter-to-endpoint attributes
- `example_schema_api.ae`: a declarative JSON API with rich `std.schema` validation +
  transforms + coercion, auto `/schema` (draft-07) and `/openapi.json` (OpenAPI 3.0)
- `schema_api/`: the `std.schema`-backed JSON API layer (`json_api`, `openapi_route`)
- `test_schema_api.ae`: schema_api integration tests (validation + schema/OpenAPI endpoints)
- `test_spec.ae`: DSL registration unit tests
- `test_integration.ae`: HTTP round-trip integration tests
- `test_streams.ae`: WebSocket, SSE and chunked endpoints and the server
  options, over loopback
