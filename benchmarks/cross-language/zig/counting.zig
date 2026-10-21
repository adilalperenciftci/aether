// Zig Counting Actor Benchmark (Savina-style)
// One counter thread receives N messages through its mailbox (mailbox.zig)
// and counts them; a final -1 tells it to stop.
const std = @import("std");
const bench = @import("bench.zig");
const Io = std.Io;
const Mailbox = @import("mailbox.zig").Mailbox;
const Slot = @import("mailbox.zig").Slot;

// 1024 messages, the mailbox size of every language here that bounds one
// (FAIRNESS.md, techniques).
var inbox_buf: [1024]Slot = undefined;
var inbox: Mailbox = undefined;
// The messages the counter took, the checksum.
var processed: i64 = 0;

fn counter(io: Io) void {
    var count: i64 = 0;
    while (inbox.receive(io) >= 0) count += 1;
    processed = count;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const messages = bench.envCount(init, "BENCHMARK_MESSAGES", 100_000);

    try bench.print(io, "=== Zig Counting Actor Benchmark ===\nMessages: {d}\n\n", .{messages});

    const start = bench.nowNs(io);

    inbox = .init(&inbox_buf, 1000);
    const thread = try std.Thread.spawn(.{}, counter, .{io});
    var i: i64 = 0;
    while (i < messages) : (i += 1) inbox.send(io, i);
    inbox.send(io, -1);
    thread.join();

    const end = bench.nowNs(io);
    if (processed != messages) std.debug.print("VALIDATION FAILED: expected {d}, got {d}\n", .{ messages, processed });
    try bench.report(io, processed, messages, end - start);
}
