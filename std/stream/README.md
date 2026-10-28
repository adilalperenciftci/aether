# std.stream

A stream between two actors whose memory stays bounded however fast the
producer is (#426).

A send never blocks. When a consumer's mailbox is full, the scheduler parks
the message in an overflow buffer that grows without bound, because blocking
the sender is how actor systems deadlock. That is right for the scheduler,
but it means a producer that outruns its consumer (a file reader feeding a
compressor, a log tailer feeding an uploader) grows the process until it
dies. A stream puts the bound back, at the stream instead of the mailbox.

The producer starts with `window` credits. Each chunk it sends costs one, and
the consumer returns one for each chunk it has handled. With no credit left
the producer stops, and it goes on when the next `StreamCredit` arrives. So
at most `window` chunks of the stream are ever in flight, and the producer
never waits: running out of credit is a return value, not a block.

```aether,run
import std.stream
import std.string

message Start { s: ptr, data: string }
message Result {}

actor Producer {
    state s: ptr = null
    state data = ""
    state at = 0
    receive {
        Start(s: st, data: d) -> {
            s = st
            data = d
            at = stream.write(s, data, 0, 4)
            if at == string.length(data) {
                stream.finish(s)
            }
        }
        StreamCredit(s: st, n) -> {
            if stream.credit(st, n) == 0 {
                s = null // the stream has ended, and is freed
            } else if at < string.length(data) {
                at = stream.write(s, data, at, 4)
                if at == string.length(data) {
                    stream.finish(s)
                }
            }
        }
    }
}

actor Consumer {
    state text = ""
    state chunks = 0
    receive {
        StreamChunk(s, data, last) -> {
            if last == 0 {
                text = string.concat(text, data)
                chunks = chunks + 1
            }
            stream.consumed(s, last)
        }
        Result() -> { reply "${chunks} chunks: ${text}" }
    }
}

main() {
    p = spawn(Producer())
    c = spawn(Consumer())
    s = stream.connect(p, c, 2)
    p ! Start { s: s, data: "a credit-windowed stream" }
    wait_for_idle()
    println(c ? Result {})
}
```
```output
6 chunks: a credit-windowed stream
```

Six chunks of four bytes went through a window of two. The producer never
had more than two out at once.

## The calls

| Call | Whose | What it does |
|---|---|---|
| `stream.connect(producer, consumer, window)` | whoever wires them | A stream with at most `window` chunks in flight, or `null` for a window under 1. Give it to both actors. |
| `stream.offer(s, data)` | producer | Sends `data` as one chunk: `1` sent, `0` the window is full (offer it again after the next credit), `-1` after `finish`. |
| `stream.write(s, data, at, chunk)` | producer | Sends `data` from byte `at` on, in chunks of at most `chunk` bytes, while the window allows. Returns the byte it reached: the length of `data` when all of it went, less when the window filled (call again from there after the next credit). |
| `stream.finish(s)` | producer | Ends the stream. The consumer gets a last chunk after every chunk sent before it. |
| `stream.credit(s, n)` | producer, for each `StreamCredit` | `1`: `n` more chunks may go. `0`: this was the consumer's end of the stream, which is freed now; drop it. |
| `stream.consumed(s, last)` | consumer, after handling each `StreamChunk` | Returns the chunk's credit or, for the last chunk, ends the stream on the consumer's side; drop it after. |
| `stream.available(s)` | producer | Chunks it may send now. |
| `stream.in_flight(s)` | producer | Chunks sent whose credit has not come back. |
| `stream.peak(s)` | producer | The most chunks that were in flight at once. Never more than the window. |

The two messages, which the program's actors handle under these names:

```aether,fragment
message StreamChunk { s: ptr, data: string, last: int }   // last 1: the end, no data
message StreamCredit { s: ptr, n: int }                   // n 0: the consumer's end
```

## How it ends, and who frees it

Messages from one sender to one actor arrive in the order sent, both ways.
So the consumer's `StreamChunk`s come in the order the producer sent them,
the last one last, and the producer's `StreamCredit`s come in the order the
consumer sent them, the end (`n` 0) last. When `stream.credit` sees the end,
every chunk has been handled and every credit has come back, so nothing of
the stream is in flight. The stream is freed there, by the producer's call.

An actor that drops out midway leaks the stream, as it would any message
addressed to it. A stream is for two actors that both run it to the end.

## Choices made

- **The unit of credit is a chunk, not a byte.** The producer picks the chunk
  size (`stream.write`'s `chunk`), so the memory a stream can hold is at most
  `window` times that size. To bound bytes, pick the chunk size and set the
  window to the budget divided by it.
- **The consumer's buffer is its mailbox.** At most `window` chunks of the
  stream are ever queued there, so the stream needs no buffer of its own.
- **A chunk is a copy.** `data` is a string, so it holds any bytes
  (`std.bytes`' `string_from_slice` makes one from a `byte[]`), and a send
  copies it. The consumer owns what it gets and the producer keeps what it
  sent, so nothing is shared across the send and no credit has to carry a
  release.
- **The read is the arm.** An actor never blocks, so a consumer reads a
  stream the way a reactor reads a socket: when data is there. Its
  `StreamChunk` arm is the read loop's body, and `last` is the end of file.
- **No sequence numbers and no reordering.** Delivery between two actors in
  one process is in order, so there is nothing to reorder. Sequencing and
  session ids belong with a transport that can lose or reorder messages, and
  will be designed with one.
- **A library, not a runtime feature.** It is a struct and two messages over
  plain sends; the scheduler is unchanged.

Run the module's tests with `ae test std/stream/test_stream.ae`. They check
order and integrity on binary data, the window bound, the end, misuse, and,
where the heap count is exact, that whole streams leak nothing.
