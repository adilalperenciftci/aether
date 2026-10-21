// What the Zig benchmarks share apart from the mailbox: the message count
// from the environment, the clock, and the lines the runner reads.
const std = @import("std");
const Io = std.Io;

/// The environment variable `name` as a number, or `default`.
pub fn envCount(init: std.process.Init, name: []const u8, default: i64) i64 {
    const val = init.environ_map.get(name) orelse return default;
    return std.fmt.parseInt(i64, val, 10) catch default;
}

pub fn nowNs(io: Io) i96 {
    return Io.Clock.awake.now(io).nanoseconds;
}

/// The lines the runner reads, on stdout.
pub fn report(io: Io, checksum: i64, count: i64, elapsed_ns_raw: i96) !void {
    const elapsed_ns: f64 = @floatFromInt(@max(elapsed_ns_raw, 1));
    const n: f64 = @floatFromInt(count);
    var buf: [256]u8 = undefined;
    var w = Io.File.stdout().writerStreaming(io, &buf);
    const out = &w.interface;
    try out.print("Checksum: {d}\n", .{checksum});
    try out.print("ns/msg:         {d:.2}\n", .{elapsed_ns / n});
    try out.print("Throughput:     {d:.2} M msg/sec\n", .{n * 1000.0 / elapsed_ns});
    try out.flush();
}

pub fn print(io: Io, comptime fmt: []const u8, args: anytype) !void {
    var buf: [256]u8 = undefined;
    var w = Io.File.stdout().writerStreaming(io, &buf);
    try w.interface.print(fmt, args);
    try w.interface.flush();
}
