# std.brotli

Brotli (RFC 7932) encoding and decoding, streaming and one-shot.

`br` is what current browsers actually prefer: every modern browser lists it
ahead of `gzip` in `Accept-Encoding`, and it typically beats gzip by 15-25% on
text at comparable speed. This module wraps the system **libbrotlienc** and
**libbrotlidec** (`apt install libbrotli-dev`, `brew install brotli`).

## Decoding

Decoding is where brotli's CVEs are, because the input is whatever a peer
sent. Every decode takes a cap on what it will produce:

```aether,fragment
body, n, err = brotli.decompress_max(string.bytes(req_body), 1048576)  // 1 MiB
```

Past the cap the decoder stops and returns `"... output limit exceeded"`.
`decompress(data)` is `decompress_max(data, 0)`, and 0 means a 1 GiB ceiling:
fine for data you produced, too generous for a request body.

The streaming decoder takes chunks of any size, and its cap covers the total:

```aether,fragment
ds, err = brotli.decompress_stream_new(1048576)
chunk, n, err = brotli.decompress_stream_write(ds, string.bytes(part))
_, _, err = brotli.decompress_stream_finish(ds)   // "truncated stream" if cut short
brotli.decompress_stream_free(ds)
```

Truncated input, corrupt input and bytes after the end of the stream are all
errors, on both paths. A failed stream refuses further writes.

### What it defends against

| Issue | Where | What this module does |
|---|---|---|
| CVE-2026-111497 ("broccoli2shell" / Node2Shell): out-of-bounds write on a malformed block switch, RCE | libbrotlidec 1.0.3-1.2.0; Node.js, Bun, Python `brotli` | Refuses to decode on an unfixed libbrotlidec (below). |
| CVE-2025-6176: decompression bomb, no output limit | Python `brotli` < 1.2.0, Scrapy | `max_bytes` on every decode; tested with 8 MiB packed into a few hundred bytes. |
| CVE-2025-66471: a small streaming read decodes a whole highly-compressed chunk | urllib3 < 2.6.0 | The stream cap counts every byte a write produces, so one write cannot exceed it. |
| CVE-2020-8927: overflow when one-shot decoding > 2 GiB | libbrotli < 1.0.8 | The one-shot path uses the streaming decoder, lengths are `int`, and the fix check below rules out pre-1.0.8 libraries. |
| Large-window streams: the header can ask for a 1 GiB window outside any output cap | non-RFC 7932 extension | Left off; a test pins that such a stream is refused. |
| Truncation read as a complete body | a common decoder-wrapper bug | `decompress_stream_finish` reports `"truncated stream"`. |

`std.http`'s client does not decode `Content-Encoding` itself, so the chained
encodings of urllib3's CVE-2025-66418 (`br, br, br, ...`) do not arise: a
caller decodes once, explicitly.

### An unfixed system libbrotlidec is refused

CVE-2026-111497 is in the system library, so linking against an old one
would make every decode exploitable. `decoder_available()` is 1 only when the
library carries the fix (upstream 1.0.10, 1.1.1, 1.2.1, or a distro backport
such as Debian's `1.0.9-2+deb12u1`); otherwise every decode returns an error
naming the CVE and encoding keeps working. The check asks the library to name
error code -17, which the fix added. A backport that keeps the old version
number still passes, where a version comparison would refuse it.

## Streaming Encoding

The surface deliberately mirrors `std.zlib`'s streaming deflate, so a server
negotiating `br` against `gzip` writes the same shape either way:

```
s, err        = brotli.stream_new(brotli.FAST_QUALITY, 0)
chunk, n, err = brotli.stream_write(s, string.bytes(ev))
chunk, n, err = brotli.stream_flush(s)      // send these bytes now
tail,  n, err = brotli.stream_finish(s)     // at connection close
                brotli.stream_free(s)
```

`stream_write` usually returns **0 bytes**: the encoder buffers internally for
compression ratio. `stream_flush` is what emits a decodable boundary while
keeping the window, so later events cost far less than the first: three
repetitive events compress to 31, 13 and 13 bytes.

A handle owns its output buffer, so two streams may be open on one thread (two
SSE connections on one event loop) without fighting over it. Always
`stream_free`.

## Quality

`quality` is 0-11. **11 is the library default and is slow**: `FAST_QUALITY`
(5) is the usual choice for a live HTTP response. `window` is the lg2 window
size (10-24); pass 0 for the library default. Both are clamped rather than
rejected, matching how `std.zlib` treats `level`.

## One-shot

```
packed, n, err = brotli.compress(string.bytes(body), brotli.FAST_QUALITY)
```

## When the backend is absent

Built without libbrotli, `available()` returns 0 and `stream_new` returns
`(null, "brotli unavailable")`. Every other stream call needs the handle, so a
program fails where it *asks for* a stream rather than silently emitting
nothing. A server negotiating content-encoding should check `available()` and
fall back to gzip.

## Exports

`available`, `decoder_available`, `compress`, `decompress`, `decompress_max`,
`stream_new`, `stream_write`, `stream_flush`, `stream_finish`, `stream_free`,
`decompress_stream_new`, `decompress_stream_write`, `decompress_stream_finish`,
`decompress_stream_free` (and the `MIN_QUALITY` / `MAX_QUALITY` /
`DEFAULT_QUALITY` / `FAST_QUALITY` constants), plus the `brotli_*` raw forms.
