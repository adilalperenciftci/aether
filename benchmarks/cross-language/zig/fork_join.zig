// Zig Fork-Join Benchmark (Savina-style)
// 8 worker threads, each with a mailbox (mailbox.zig); main sends the
// messages round-robin, then a -1 to each, and joins them.
const std = @import("std");
const bench = @import("bench.zig");
const Io = std.Io;
const Mailbox = @import("mailbox.zig").Mailbox;
const Slot = @import("mailbox.zig").Slot;

const NUM_WORKERS = 8;

// 1024 messages, the mailbox size of every language here that bounds one
// (FAIRNESS.md, techniques).
var bufs: [NUM_WORKERS][1024]Slot = undefined;
var inbox: [NUM_WORKERS]Mailbox = undefined;
var processed: [NUM_WORKERS]i64 = [_]i64{0} ** NUM_WORKERS;
var sums: [NUM_WORKERS]i64 = [_]i64{0} ** NUM_WORKERS; // the values each worker received

fn worker(io: Io, id: usize) void {
    var n: i64 = 0;
    var s: i64 = 0;
    while (true) {
        const value = inbox[id].receive(io);
        if (value < 0) break;
        s += value;
        n += 1;
    }
    processed[id] = n;
    sums[id] = s;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const per_worker = @divTrunc(bench.envCount(init, "BENCHMARK_MESSAGES", 100_000), NUM_WORKERS);
    const total = per_worker * NUM_WORKERS;

    try bench.print(io, "=== Zig Fork-Join Throughput Benchmark ===\nWorkers: {d}, Messages: {d}\n\n", .{ NUM_WORKERS, total });

    const start = bench.nowNs(io);

    var threads: [NUM_WORKERS]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        inbox[i] = .init(&bufs[i], 1000);
        t.* = try std.Thread.spawn(.{}, worker, .{ io, i });
    }
    var i: i64 = 0;
    while (i < total) : (i += 1) inbox[@intCast(@mod(i, NUM_WORKERS))].send(io, i);
    for (&inbox) |*m| m.send(io, -1);
    for (threads) |t| t.join();

    const end = bench.nowNs(io);

    var total_processed: i64 = 0;
    var checksum: i64 = 0;
    for (processed, sums) |n, s| {
        total_processed += n;
        checksum += s;
    }
    if (total_processed != total) std.debug.print("VALIDATION FAILED: expected {d}, got {d}\n", .{ total, total_processed });
    try bench.report(io, checksum, total, end - start);
}
