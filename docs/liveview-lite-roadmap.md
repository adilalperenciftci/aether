# LiveView-lite: a roadmap (Phoenix LiveView, on actors, without the framework)

## Where this comes from

Phoenix **LiveView** keeps a stateful, server-rendered view alive over a
WebSocket: the server holds per-connection state (`assigns`), a `~H` template
compiler splits markup into static and dynamic parts, and every event pushes
only the *diff* down to a tiny JS client that patches the DOM (morphdom). No
client-side framework, no hand-written API, no client state to keep in sync:
the server is the source of truth and the wire carries minimal patches.

The idea maps cleanly onto things Aether already has:

| LiveView concept        | Aether primitive |
|-------------------------|------------------|
| per-connection process holding `assigns` | an actor / the connection's `ctx` map |
| the transport            | `contrib/tinyweb` WebSocket (`web_socket(path) \|msg, sender, ctx\|`) |
| `handle_event`           | the WS message handler |
| `render` → push          | `http.ws_send_text(sender, html)` |
| the JS client            | ~15 lines: on message swap innerHTML, on click `ws.send(...)` |

The question this doc answers: *how much of LiveView is worth building on
Aether, and where is the line?*

## The thesis worth stealing

LiveView's superpower is: **one stateful server-side view, rendered from state,
pushing minimal updates over a persistent connection: the client is a thin
renderer, not an application.** You write server code; interactivity falls out.

That is a genuinely good fit for Aether: the state lives in an actor (Aether's
native concurrency unit), the render is a pure `state -> html` function, and the
transport already exists in `contrib/tinyweb`. What LiveView layers on top
(the `~H` diffing compiler, the `phx-*` binding vocabulary, presence/PubSub) is
where the weight is, and where we choose carefully.

## What the spike already proved

A working prototype (scratchpad `counter_live2.ae` + a Python `websocket-client`
driver) drives the **full loop** on Aether's own primitives, with no `~H`
compiler and no JS framework:

```
mount        -> 0
{"event":"inc"} -> 1
{"event":"inc"} -> 2
{"event":"dec"} -> 1
{"event":"reset"} -> 0
ALL PASS: the LiveView loop (mount/handle_event/render/push) works
```

- Per-connection state kept server-side in the handler's `ctx`, the map a
  connection's messages share: tinyweb's `web_socket` handler is shared, the
  `ctx` is the connection's.
- `render(state) -> html` is a pure function; the whole `#live` region is pushed
  as one frame (full-HTML replace: no diffing yet; the point was the *loop*).
- Client events (`{"event":"inc"}`) arrive, mutate state, re-render, push back.

The spike's real yield was flushing out that tinyweb's WebSocket/SSE **server**
path had never run a live connection and had rotted. The six defects found there
(frame unmasking, header-byte encoding, extended-length NUL truncation, tuple
drift, boxed-closure dispatch, a request-path use-after-free) shipped in
**PR #1449 (merged)**: that is the durable output so far, independent of whether
LiveView-lite proceeds.

### Spike artifacts (start here)

The prototype is the single most useful thing to read before building, and it is
**committed** under `contrib/tinyweb/examples/liveview/`:

- **`contrib/tinyweb/examples/liveview/example_counter_live.ae`**: the working WS-only
  spike, a `web_socket` route served by `tw_start`. Also reproduced in
  [Appendix A](#appendix-a-the-working-spike-source) for at-a-glance reading.
- **`contrib/tinyweb/examples/liveview/drive_live.py`**: a Python
  `websocket-client` driver asserting `mount→0, inc→1, inc→2, dec→1, reset→0`.
  Reproduced in [Appendix B](#appendix-b-the-python-driver).
- **`contrib/tinyweb/examples/liveview/README.md`**: build/run instructions.
- **`contrib/tinyweb/test_streams.ae`**: tinyweb's WebSocket, SSE and chunked
  round trips. The `live_view` round-trip test (A.5) should mirror its
  structure (`tw_start` in an actor, std.http's WebSocket client in `main`,
  std.spec cases).

Build the spike:
`ae build contrib/tinyweb/examples/liveview/example_counter_live.ae -o /tmp/counter_live`

## The honest strategic read: how big a bet is this?

Be candid, not cheerleading: **full LiveView is a qualitatively bigger and
riskier ambition than the Ash/schema projection work.** It is a multi-month
flagship project (Aether's most ambitious "we can do full-stack" statement) not
a natural next increment. It lands squarely in the runtime/framework tier the
schema roadmap flagged as "not yet." Three cost drivers make it a different
*order* of commitment:

1. **It's inherently stateful and runtime-heavy.** The whole model rests on a
   persistent per-connection process holding UI state. In Elixir that's a
   lightweight, supervised, fault-tolerant BEAM process: millions of them,
   cheap. Aether has actors (`spawn`/`receive`), which is the *right* primitive,
   but "a supervised stateful process per browser tab, for thousands of tabs" is
   a serious scheduler/runtime load story on a manual-memory, compiles-to-C
   model. This is Tier-C framework/runtime weight, not pure projection.
2. **The magic is a compiler feature, not a library.** LiveView's efficiency
   comes from its template compiler splitting static vs dynamic and computing
   minimal diffs. A `~H`-equivalent template DSL + change-tracking is a real
   chunk of the Aether compiler, not a `contrib` module.
3. **It needs the JS client half.** morphdom-style DOM patching, the WebSocket
   protocol, event wiring: a client-side runtime (tens of KB of JS) that has to
   ship and stay in protocol-sync with the server. Owning both sides of a wire
   protocol is an ongoing maintenance surface.

But the pieces exist in embryo: tinyweb already serves WebSocket and SSE routes
(std.http's); Aether has actors for per-connection state;
`std.schema` / templating exist. So it's conceivable, not fantasy.

**The on-ramp (why this is not either/or with the schema roadmap):** an
Ash-style schema resource is *exactly what a LiveView renders and edits*,
live-beats is Ecto/Ash resources projected into a real-time UI. So
projection-first is the on-ramp: once `std.schema` can `to_form_html()` (schema
roadmap Tier A.5), a "live" version just adds the WebSocket-diff loop on top. The
static form is the cheap, safe first surface; the live form is the same
declaration with the loop bolted on.

**Decision taken (2026-08-08):** rather than spec the whole flagship unprompted,
the chosen first move was a **LiveView-lite spike**: prove the loop end-to-end
on the existing primitives, learn what breaks, and defer the compiler/JS/runtime
investment until the loop itself is proven and wanted. The spike (above) did
exactly that. This roadmap is the "if we swing bigger, here's the staged path"
that the spike earned: deliberately incremental, with the flagship-scale pieces
(diff compiler, full JS client) explicitly gated behind demonstrated demand.

## The strategic line

Aether is a systems language that compiles to readable C with **no GC and a
manual-memory model**, not an Elixir/OTP application framework. So:

- **Lean into the stateful-view loop** (actor holds state, pure render, push over
  WS). This is LiveView's most distinctive idea and the part that fits Aether
  best: it is just actors + a pure function + an existing transport.
- **Add client-facing machinery only where it removes real boilerplate**: a
  static/dynamic diff (so pushes are small), and a small `phx-*` binding
  vocabulary (so handlers get named events, not raw strings).
- **Stay out of the OTP-ecosystem tiers.** Cluster-wide Presence, distributed
  PubSub, LiveComponents-as-a-framework, live navigation/routing as a subsystem:
  that's Elixir/BEAM weight (process distribution, a supervision-tree culture)
  that a single-node systems runtime shouldn't grow into `std`. If any of it is
  wanted, it belongs in `contrib/*`, consumed explicitly.

## The structural blocker (cleared)

tinyweb used to listen for WebSocket and SSE on ports of their own, with loops
of its own that nothing ran while `tw_start` blocked in the HTTP accept loop,
so a program could not serve the page and the live channel at once. Since
#3109, `web_socket` and `sse_endpoint` routes are std.http's, on the HTTP
port: `tw_start` serves the initial HTML, the WebSocket and SSE together, and
the spike runs through it. The server map built by the DSL crosses an actor
message intact (`test_schema_api.ae` and `test_streams.ae` both start the
server from one).

## Wire protocol

The protocol is deliberately tiny and versioned so the server and the (browser)
JS client can evolve together. All frames are WebSocket **text** frames carrying
UTF-8 JSON. `http.ws_send_text` (server→client) and the browser's
`ws.send` (client→server) are the transports; std.http's codec unmasks
inbound frames and reassembles fragmented ones.

**Client → server** (one JSON object per frame):

```jsonc
// A1/A2: the spike accepts a bare string ("mount", "inc"); DO NOT keep that.
// From A3 on, the client always sends this envelope:
{ "t": "event",  "event": "inc",   "value": { "amount": 1 } }   // phx-click / phx-value-*
{ "t": "event",  "event": "save",  "value": { "name": "ada", "email": "a@b.c" } } // phx-submit (form fields)
{ "t": "mount" }                                                 // first frame after connect
{ "t": "ping" }                                                  // optional keepalive
```

- `t` is the frame type; `event` is the app-defined event name from the `phx-*`
  attribute; `value` is a JSON object (never a bare scalar: always an object so
  the shape is stable). Forms send their fields as `value`.

**Server → client** (one JSON object per frame):

```jsonc
// A1/A2: the spike sends raw HTML with no envelope. From A3 on:
{ "t": "render", "html": "<div id=\"live\">…</div>" }            // full-HTML replace (A2/A3)
{ "t": "diff",   "slots": { "0": "1", "2": "user" } }           // A4: only changed dynamic slots
{ "t": "error",  "code": 404, "message": "no live view at /x" }
```

- **A2/A3** use `{"t":"render","html":…}`: client does
  `document.getElementById("live").outerHTML = msg.html`.
- **A4** switches to `{"t":"diff","slots":…}` where each key is a dynamic-slot
  index (see the diffing sketch under A4) and the value is that slot's new
  rendered string. The client keeps the static skeleton from the initial render
  and substitutes changed slots. The **first** post-mount frame is always a full
  `render` (client needs the skeleton); subsequent frames are `diff`.

**Framing invariant:** each protocol message is exactly one WebSocket message.
std.http's codec takes any length (payloads will exceed 126 bytes, and can
exceed 64 KiB).

## Module & API surface

Everything lives in **`contrib/tinyweb/live_view/`** (a new sibling of
`schema_api/`), consumed as `import contrib.tinyweb.live_view`. It builds on the
existing tinyweb WS API: no core/`std` changes. Reference signatures the
implementer should target (names may be refined, shapes should not):

```aether,fragment
// contrib/tinyweb/live_view/module.ae

// A per-connection live view is three caller-supplied closures. `assigns` is an
// opaque ptr (a std.map) the framework stores per connection and hands back.
//
//   mount(sender, assigns)              -> assigns   // seed initial state
//   handle_event(sender, ev, assigns)   -> assigns   // ev = parsed {event,value}
//   render(assigns)                     -> string    // HTML for the live region
//
// Register one live view at a WS path. Returns a ws_entry-shaped map to add to
// the ws_handlers list (or the DSL registers it for you: see live_view_route).
live_view(path: string, mount: fn, handle_event: fn, render: fn) -> ptr

// DSL sugar for use inside a web_server { ... } block, mirroring
// web_socket(...). Registers the live view on the server's ws_handlers.
live_view_route(_ctx: ptr, path: string, mount: fn, handle_event: fn, render: fn)

// --- per-connection state store (generalizes the spike's ctx attributes) ---
// Held in the connection's ctx, the web_socket handler's third argument.
// assigns_get lazily mounts.
assigns_new()                              -> ptr           // fresh empty assigns map
assign(assigns: ptr, key: string, val: string)             // set one field
assign_get(assigns: ptr, key: string)      -> string       // read one field (\"\" if absent)

// --- event parsing (A3) ---
// Parse an inbound client frame into a typed event. Returns (type, event, value_json).
parse_frame(msg: string)                    -> (string, string, ptr)   // (t, event, value-map)

// --- the client runtime (A3+) ---
// Returns the inline <script> the page must include: opens the WS to the live
// path, sends {t:"mount"}, wires phx-click/phx-submit/phx-value-*, and applies
// {t:"render"} / {t:"diff"} frames. Kept small and dependency-free.
client_js(ws_path: string)                  -> string
```

**Per-connection lifecycle & cleanup:** `assigns` for a connection is created on
`mount` and must be **freed when the connection closes**. tinyweb frees the
connection's `ctx` when the connection closes, so assigns kept there as ctx
attributes go with it; anything the `live_view` keeps outside `ctx` (an
assigns map stored by pointer) needs a close hook of its own, or it leaks for
every disconnect.

## Tiers

Each tier below carries **explicit acceptance criteria**: the definition of
"done" a reviewer checks, not just a description.

### Tier A: the loop as a reusable shape (the plan)

**A1. Concurrent serve** (done, #3109): one program serves the initial HTML
over HTTP *and* the live channel over WS at the same time, on one port, through
`tw_start` (see "The structural blocker (cleared)").

**A2. A `live_view` handler shape in `contrib/tinyweb/live_view`**: wrap the raw
`web_socket` handler into the `mount` / `handle_event(sender, ev, assigns) ->
assigns` / `render(assigns) -> html` triple (signatures above), with
per-connection `assigns` stored in the connection's `ctx` (generalizing the
spike's ctx attributes). Full-HTML push via `{"t":"render","html":…}`: correct,
not yet minimal. Free whatever assigns keep outside `ctx` on close.
- **Acceptance:** the counter is re-expressible as three closures passed to
  `live_view(...)` with **zero** hand-written WS/frame code in the app; two
  concurrent connections keep independent counts (state is per-connection, not
  global); disconnecting one frees its `assigns` (valgrind: no per-connection
  leak across N connect/disconnect cycles).

**A3. `phx-*` binding vocabulary (thin)**: adopt the wire envelope above. The
client runtime (`client_js`) parses `phx-click="inc"`, `phx-submit="save"`, and
`phx-value-*="…"` from the DOM and sends `{"t":"event","event":…,"value":{…}}`;
the server's `parse_frame` turns that back into `(t, event, value-map)` delivered
to `handle_event`. No app hand-rolls `ws.send(JSON.stringify(...))`.
- **Acceptance:** an app declares `phx-click="inc"` with no JS of its own and the
  server receives `event="inc"`; a `phx-submit` form delivers its fields as a
  `value` map; malformed inbound frames are rejected with `{"t":"error",…}` and
  do not crash the loop. `client_js` output is < a few KB and has no external
  deps (CSP-clean, inlineable).

**A4. Static/dynamic diffing**: the LiveView payoff and the highest-risk step.
A template is *projected* into a static skeleton + indexed dynamic slots; a
re-render pushes only the changed slots (`{"t":"diff","slots":{…}}`) and the
client substitutes them in place. This is the same "one declaration → minimal
artifact" muscle as the schema projections. Build all string work over
`strbuilder` (leak-clean), never a server-side DOM.

  *Algorithm sketch (first-render split, no new compiler syntax required):*
  1. Model a template as an **alternating list**: `[static, {slot 0}, static,
     {slot 1}, static, …]`. In the simplest form a "template" is a function
     `render_parts(assigns) -> (statics: list<string>, dynamics: list<string>)`
     where `statics` is fixed for the template and `dynamics[i]` is the rendered
     value of slot `i` for the current `assigns`. (An app writes this by hand at
     first; a `~H`-like macro that generates it is a *later* nicety, explicitly
     not required for A4.)
  2. **First render** (post-mount): send `{"t":"render","html":…}` built by
     interleaving `statics` and `dynamics`, AND cache `dynamics` server-side per
     connection as `prev_dynamics`.
  3. **Subsequent renders:** compute `dynamics'` from the new `assigns`, diff
     element-wise against `prev_dynamics`, and send
     `{"t":"diff","slots":{ i: dynamics'[i] for i where dynamics'[i] != prev }}`.
     Update `prev_dynamics`.
  4. **Client:** on the first `render`, store the static skeleton (it can rebuild
     the alternating structure because the server also sends the slot count, or
     the client re-requests a full render on desync). On each `diff`, replace the
     text of slot `i`. Keep this to innerText/attribute substitution: no
     morphdom needed for the leaf case; a nested/structural diff is a later
     extension, out of scope for A4.
  - *Risk note:* the hard part is defining what a "slot" is when dynamics contain
    nested markup or lists. A4's scope is **flat, text/attribute slots** (the
    counter, a form's field values/errors). Structural/list diffing (LiveView's
    comprehensions) is deferred and should be called out as such when A4 lands:
    do not silently ship a half-diff.
  - **Acceptance:** for the counter, incrementing sends a `diff` whose `slots`
    contains only the changed count, not the whole HTML (assert the frame is
    smaller than the full render and contains the new value); the client shows the
    updated count; a from-scratch client (fresh connect) still gets a correct full
    first render. Round-trip test proves both the full-render and diff frames.

**A5. A runnable showcase + test**: promote the counter spike into
`contrib/tinyweb/example_live_view.ae` (a real page: served HTML + live region +
inlined `client_js`), plus `contrib/tinyweb/test_live_view.ae`, a WS round-trip
test **mirroring `test_streams.ae`** (`tw_start` in an actor, std.http's
WebSocket client in `main`, std.spec cases).
- **Acceptance:** `test_live_view.ae` drives `mount→0, inc→1, inc→2, dec→1,
  reset→0` over a real WS connection and passes; reverting A4's diff logic makes
  the diff-frame assertion fail (the test guards the feature). Test lives in
  `contrib/` (not in the `test-ae` CI glob) and is listed in
  `.github/scripts/contrib_check.sh`.

A shared spine: the `live_view` module every example uses, so a new live page is
a `mount`/`render`/`handle_event` triple, not re-plumbing the WS accept loop.

### Tier B: modeling depth (only with a concrete consumer)

- **Server-pushed updates** (`send_update` / a timer or actor message re-rendering
  a live view without a client event): the "live dashboard" case. Maps onto an
  actor message into the connection's state. Useful; modest.
- **Forms + `std.schema`**: bind a live form to a `std.schema` `record`:
  validate on `phx-change`, push per-field errors back, submit on valid. This is
  where the two roadmaps meet: the schema resource is the contract, LiveView is
  one more surface it projects into (a live, validating form). High value, and it
  reuses work already planned in `docs/schema-projection-roadmap.md`.
- **`phx-hook` escape hatch**: a named JS hook for the cases a diff can't
  express (a chart, a map). Small, opt-in.

### Tier C: explicitly out of scope

Cluster-wide Presence, distributed PubSub, a LiveComponent framework, live
navigation/routing as a subsystem, and anything assuming BEAM process
distribution or a supervision-tree culture. That is Elixir/OTP-ecosystem weight
that does not map to a single-node systems runtime. If wanted, it lives in
`contrib/*` and is consumed explicitly: never welded into `std` or the core
tinyweb library.

## Known landmines (read before writing code)

These bit us building the spike and PR #1449. Each one costs an afternoon if
rediscovered.

- **`string.array_get` returns a BORROWED pointer.** After `string.array_free`,
  anything from `array_get` dangles. When parsing the request/path or form
  fields, mint an owned copy first: `x = string.concat(string.array_get(a,i),"")`
  before freeing the array. This was the `?/�3V`-garbage-path 404 bug.
- **Boxed closures: keep them boxed until call time.** In the WS dispatch loop,
  store the handler as `hboxed` (a `ptr`, `null` when absent) and only
  `unbox_closure(hboxed)` immediately before `call(...)`. Unboxing into a slot at
  lookup and invoking later leaks/segfaults (fixed in #1449; the `live_view`
  dispatch follows the same shape).
- **Inbound client frames are masked; server frames are not.** std.http's
  codec unmasks (RFC 6455 §5.3), and its client masks. If you write a raw test
  client, YOU must mask client→server frames, building each frame in a
  `std.bytes` buffer (see `ping` in `test_streams.ae`), or use
  `http.ws_connect`.
- **TCP reads are short reads.** `tcp.read(n)` / `read_n(n)` may return fewer
  than `n` bytes. A client reading a server frame must loop until it has the
  declared length (see `read_exact` in `test_streams.ae`).
- **Test-server hygiene under the Bash tool.** Aborted `.ae` server tests orphan
  `~/.aether/cache/<hex>` binaries that busy-loop and **squat the port**: the
  hidden cause of "flaky" bind failures. Launch detached
  (`setsid … < /dev/null &` + a PID file), tear down by PID, and pick a fresh
  port per run. A leading `pkill` that matches nothing returns non-zero and
  poisons a compound Bash command (`exit 144`); run cleanup as its own step.
- **`println` buffering.** A blocking server killed mid-run loses buffered
  stdout; use `stdbuf -oL` (or `exit(0)` to flush) when capturing server logs.
- **`bytes.new(n)` is not zeroed.** If you don't write every byte, set the top
  index first to force zero-fill. The frame builders write every byte, so this is
  only a concern for partial buffers.

## Why this is a reasonable bet for Aether

- **It's actors + a pure function + an existing transport.** No new runtime: the
  state lives in an actor, `render` is pure, the WebSocket is already there
  (std.http's, on the HTTP port).
- **The diff is a projection.** Splitting a template into static skeleton +
  dynamic slots and shipping only slots is the same "one declaration → minimal
  artifact" muscle as the schema projections: pure, leak-free over `strbuilder`,
  no DOM on the server.
- **It compounds with `std.schema`.** A live, validating form is just the schema
  resource projected onto the LiveView surface; each roadmap makes the other more
  valuable.

## Concrete next steps (if pursued)

1. Extract a `contrib/tinyweb/live_view` handler shape (A.2) and promote the
   counter spike into `example_live_view.ae` + a round-trip test (A.5).
2. Add the `phx-*` vocabulary (A.3), then the static/dynamic diff (A.4).
3. Revisit Tier B (server push, schema-bound forms) only when a real page asks
   for it.

## Relationship to the other roadmap

This doc is the **transport/interaction** half; `docs/schema-projection-roadmap.md`
is the **data/contract** half. They intersect at Tier B's schema-bound live
forms: one `std.schema` `record`, projected simultaneously into its JSON Schema /
OpenAPI (schema roadmap) *and* into a live, validating form (this roadmap).

Credits: the stateful-view-over-WebSocket-with-minimal-diffs framing is Phoenix
LiveView's (Chris McCord / the Phoenix team; MIT). Aether takes the *idea* (the
loop and the diff-as-projection), and deliberately not the OTP/BEAM framework.

---

## Appendix A: the working spike source

Committed at `contrib/tinyweb/examples/liveview/example_counter_live.ae` (reproduced here
for at-a-glance reading; the committed file is the source of truth). A
`web_socket` route served by `tw_start`. This is the A0 baseline the tiers
build on. Build:
`ae build contrib/tinyweb/examples/liveview/example_counter_live.ae -o /tmp/counter_live`.
Note it uses the *pre-A3* bare-string protocol (`"mount"`, and JSON that
`string_contains` sniffs): A3 replaces that with the wire envelope above.

```aether,nolink
// LiveView-lite SPIKE — proves the core LiveView loop on tinyweb's WebSocket
// route and Aether's own primitives, WITHOUT the template-diff compiler or a
// JS framework.
//
//   mount        -> per-connection assigns (a counter), kept server-side
//   render       -> HTML from assigns
//   phx-click    -> client sends {"event":"inc"} over the WebSocket
//   handle_event -> mutate assigns -> re-render -> push the new HTML
//
// The assigns live in the handler's `ctx`, the map a connection's messages
// share, so each browser tab has its own count.

import contrib.tinyweb
import std.http
import std.string(string_contains, to_int, string_concat)

// ---- render: assigns -> the live region's HTML ----
fn render(count: int) -> string {
    h = "<div id=\"live\">"
    h = string_concat(h, "<h1>count: ${count}</h1>")
    h = string_concat(h, "<button onclick=\"send('dec')\">-</button> ")
    h = string_concat(h, "<button onclick=\"send('inc')\">+</button> ")
    h = string_concat(h, "<button onclick=\"send('reset')\">reset</button>")
    h = string_concat(h, "</div>")
    return h
}

// ---- handle_event: mutate assigns per the client event ----
fn handle_event(ctx: ptr, event: string) -> int {
    n, _ = to_int(tinyweb.ctx_get_attribute(ctx, "count"))
    if string_contains(event, "inc") == 1 {
        n = n + 1
    } else if string_contains(event, "dec") == 1 {
        n = n - 1
    } else if string_contains(event, "reset") == 1 {
        n = 0
    }
    tinyweb.ctx_set_attribute(ctx, "count", "${n}")
    return n
}

main() {
    println("LiveView-lite counter — WebSocket on ws://127.0.0.1:8126/live  (Ctrl-C to stop)")

    server = tinyweb.web_server_host("127.0.0.1", 8126) {
        tinyweb.web_socket("/live") | msg: string, sender: ptr, ctx: ptr | {
            // "mount" hits no branch -> the current count (0 on the first frame).
            http.ws_send_text(sender, render(handle_event(ctx, msg)))
        }
    }

    err = tinyweb.tw_start(server)
    if err != "" { println("ERROR: ${err}") }
}
```

## Appendix B: the Python driver

Committed at `contrib/tinyweb/examples/liveview/drive_live.py`. Requires
`websocket-client` (`pip install websocket-client`). Run the spike detached
first, then this. It sends the pre-A3 bare-string protocol; update it to the
wire envelope alongside A3.

```python
#!/usr/bin/env python3
# Asserts the loop: mount -> 0, inc -> 1, inc -> 2, dec -> 1, reset -> 0
import re
from websocket import create_connection

URL = "ws://127.0.0.1:8126/live"

def count_of(html):
    m = re.search(r"count:\s*(-?\d+)", html)
    assert m, f"no count in frame: {html!r}"
    return int(m.group(1))

def step(ws, msg, expect):
    ws.send(msg)
    got = count_of(ws.recv())
    ok = "OK" if got == expect else "FAIL"
    print(f"  send {msg!r:24} -> count {got:<3} (expected {expect})  [{ok}]")
    assert got == expect, f"expected {expect}, got {got}"

ws = create_connection(URL, timeout=5)
try:
    step(ws, "mount", 0)
    step(ws, '{"event":"inc"}', 1)
    step(ws, '{"event":"inc"}', 2)
    step(ws, '{"event":"dec"}', 1)
    step(ws, '{"event":"reset"}', 0)
    print("ALL PASS: the LiveView loop (mount/handle_event/render/push) works")
finally:
    ws.close()
```
