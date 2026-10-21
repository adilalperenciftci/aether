// Zig Skynet Benchmark
// Based on https://github.com/atemerev/skynet
// Uses std.Thread while the subtree is larger than SEQ_THRESHOLD.
// Spawning 1M OS threads is not feasible; limits concurrent threads to ~1000.

const std = @import("std");
const bench = @import("bench.zig");
const Thread = std.Thread;

const SEQ_THRESHOLD: i64 = 1000;

fn skynetSeq(offset: i64, size: i64) i64 {
    var sum: i64 = 0;
    var i: i64 = 0;
    while (i < size) : (i += 1) {
        sum += offset + i;
    }
    return sum;
}

const SkynetArg = struct {
    offset: i64,
    size: i64,
    result: i64 = 0,
};

fn skynetThread(arg: *SkynetArg) void {
    const offset = arg.offset;
    const size = arg.size;

    if (size <= SEQ_THRESHOLD) {
        arg.result = skynetSeq(offset, size);
        return;
    }

    const child_size = @divTrunc(size, 10);
    var children: [10]SkynetArg = undefined;
    var threads: [10]Thread = undefined;

    for (0..10) |i| {
        children[i] = .{ .offset = offset + @as(i64, @intCast(i)) * child_size, .size = child_size };
        // A unit that cannot be created is a failed run, as in the other
        // languages, not a subtree summed on this thread instead.
        threads[i] = Thread.spawn(.{}, skynetThread, .{&children[i]}) catch |err|
            std.debug.panic("skynet: cannot spawn a thread: {s}", .{@errorName(err)});
    }

    var sum: i64 = 0;
    for (0..10) |i| {
        threads[i].join();
        sum += children[i].result;
    }
    arg.result = sum;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const num_leaves = bench.envCount(init, "SKYNET_LEAVES", bench.envCount(init, "BENCHMARK_MESSAGES", 1_000_000));

    // Units created; also the divisor. See FAIRNESS.md.
    var total_actors: i64 = 1;
    var n = num_leaves;
    while (n > SEQ_THRESHOLD) : (n = @divTrunc(n, 10)) {
        total_actors += @divTrunc(n, SEQ_THRESHOLD);
    }

    try bench.print(io, "=== Zig Skynet Benchmark ===\nLeaves: {d}, concurrency units: {d} (sequential below {d})\n\n", .{ num_leaves, total_actors, SEQ_THRESHOLD });

    var root = SkynetArg{ .offset = 0, .size = num_leaves };

    const start = bench.nowNs(io);
    const root_thread = try Thread.spawn(.{}, skynetThread, .{&root});
    root_thread.join();
    const end = bench.nowNs(io);

    try bench.print(io, "Sum: {d}\n", .{root.result});
    // Always printed, as in every language here: a tree small enough to
    // finish within a microsecond used to print no rate at all.
    try bench.report(io, root.result, total_actors, end - start);
}
