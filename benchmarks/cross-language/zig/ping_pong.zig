// Zig ping-pong benchmark: two std.Thread threads, each with a mailbox
// (mailbox.zig). Ping sends 0, 1, 2, ...; pong echoes each value back;
// ping checks it.
const std = @import("std");
const bench = @import("bench.zig");
const Io = std.Io;
const Mailbox = @import("mailbox.zig").Mailbox;
const Slot = @import("mailbox.zig").Slot;

var to_ping_buf: [1]Slot = undefined;
var to_pong_buf: [1]Slot = undefined;
// One message in flight each way, so a mailbox of one slot.
var to_ping: Mailbox = undefined;
var to_pong: Mailbox = undefined;
// The sum of the values ping got back, which the runner checks.
var checksum: i64 = 0;

fn ping(io: Io, messages: i64) void {
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < messages) : (i += 1) {
        to_pong.send(io, i);
        const received = to_ping.receive(io);
        sum += received;
        if (received != i) std.debug.print("ERROR: Ping sent {d} but got back {d}\n", .{ i, received });
    }
    checksum = sum;
}

fn pong(io: Io, messages: i64) void {
    var i: i64 = 0;
    while (i < messages) : (i += 1) {
        const received = to_pong.receive(io);
        if (received != i) std.debug.print("ERROR: Pong expected {d} but got {d}\n", .{ i, received });
        to_ping.send(io, received);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const messages = bench.envCount(init, "BENCHMARK_MESSAGES", 100_000);

    try bench.print(io, "=== Zig Ping-Pong Benchmark ===\nMessages: {d}\nUsing std.Thread with atomic mailboxes (spin, then sleep)\n\n", .{messages});

    const start = bench.nowNs(io);

    to_ping = .init(&to_ping_buf, 1000);
    to_pong = .init(&to_pong_buf, 1000);
    const t1 = try std.Thread.spawn(.{}, ping, .{ io, messages });
    const t2 = try std.Thread.spawn(.{}, pong, .{ io, messages });
    t1.join();
    t2.join();

    const end = bench.nowNs(io);
    try bench.report(io, checksum, messages, end - start);
}
