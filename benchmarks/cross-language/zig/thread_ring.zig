// Zig Thread Ring Benchmark (Savina-style)
// 100 std.Thread threads in a ring, each with a mailbox (mailbox.zig), pass
// a token that counts down from the hop count; the node that receives 0
// tells main.
const std = @import("std");
const bench = @import("bench.zig");
const Io = std.Io;
const Mailbox = @import("mailbox.zig").Mailbox;
const Slot = @import("mailbox.zig").Slot;

const RING_SIZE = 100;

// One token in the ring, so a mailbox of one slot.
var bufs: [RING_SIZE][1]Slot = undefined;
var inbox: [RING_SIZE]Mailbox = undefined;
var done_buf: [1]Slot = undefined;
var done_box: Mailbox = undefined; // main's: the node that gets 0 writes here
var received: [RING_SIZE]i64 = [_]i64{0} ** RING_SIZE;

fn node(io: Io, id: usize) void {
    const next = &inbox[(id + 1) % RING_SIZE];
    while (true) {
        const token = inbox[id].receive(io);
        if (token < 0) break; // main's stop, after the run
        received[id] += 1;
        if (token == 0) {
            done_box.send(io, 0);
        } else {
            next.send(io, token - 1);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const hops = bench.envCount(init, "BENCHMARK_MESSAGES", 100_000);

    try bench.print(io, "=== Zig Thread Ring Benchmark ===\nRing size: {d}, Hops: {d}\n\n", .{ RING_SIZE, hops });

    const start = bench.nowNs(io);

    // No spinning: a node waits about 99 hops for the token, and 100
    // spinning threads on fewer cores take the CPU from the one thread that
    // holds it (FAIRNESS.md, wait strategies).
    done_box = .init(&done_buf, 0);
    for (&inbox, &bufs) |*m, *b| m.* = .init(b, 0);
    var threads: [RING_SIZE]std.Thread = undefined;
    for (&threads, 0..) |*t, i| t.* = try std.Thread.spawn(.{}, node, .{ io, i });

    inbox[0].send(io, hops);
    _ = done_box.receive(io);

    const end = bench.nowNs(io);

    // The token is spent and nothing sends any more: stop every node.
    for (&inbox) |*m| m.send(io, -1);
    for (threads) |t| t.join();

    // The receipts summed over the ring, the checksum.
    var receipts: i64 = 0;
    for (received) |r| receipts += r;
    try bench.report(io, receipts, hops + 1, end - start);
}
