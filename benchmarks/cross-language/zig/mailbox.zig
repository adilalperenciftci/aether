// A mailbox for one sending thread and one receiving thread on std.atomic
// and the futex std.Io provides: the same design as c/mailbox.h, a bounded
// ring with a sequence number in each slot, so neither side reads the
// other's index and a message moves the cache line of its slot and nothing
// else. A receiver that finds its slot empty spins up to `spin` pauses,
// looking again after 1, 2, 4, ... 64 of them, then sleeps on the futex of
// the slot's sequence; a sender that finds its slot full spins, then yields:
// the receiver is running then (it sleeps only on an empty slot).
//
// Zig's std has a channel too, std.Io.Queue, a bounded queue under a mutex
// and a condition variable, and FAIRNESS.md records how it measured against
// this; the patterns here have one sender per mailbox, the shape this ring
// is for.
const std = @import("std");
const Io = std.Io;
const Atomic = std.atomic.Value;

pub const Slot = struct {
    // i: free for the sender's i-th message; i + 1: holds it. 32 bits, the
    // futex word; it wraps, and the ring is far smaller than 2^32.
    seq: Atomic(u32),
    value: i64,
};

pub const Mailbox = struct {
    head: u32 align(std.atomic.cache_line) = 0, // the receiver's next message
    tail: u32 align(std.atomic.cache_line) = 0, // the sender's next message
    // Set while the receiver sleeps, so a send makes the wake call only then.
    sleeping: Atomic(u32) align(std.atomic.cache_line) = .init(0),
    mask: u32,
    spin: u32,
    slots: []Slot,

    /// slots.len: the capacity, a power of two. spin: the pauses a receiver
    /// spends before it sleeps.
    pub fn init(slots: []Slot, spin: u32) Mailbox {
        for (slots, 0..) |*s, i| s.* = .{ .seq = .init(@intCast(i)), .value = 0 };
        return .{ .mask = @intCast(slots.len - 1), .spin = spin, .slots = slots };
    }

    pub fn send(m: *Mailbox, io: Io, value: i64) void {
        const t = m.tail;
        const s = &m.slots[t & m.mask];
        if (s.seq.load(.acquire) != t) {
            var spun: u32 = 0;
            var step: u32 = 1;
            while (s.seq.load(.acquire) != t) {
                if (spun < m.spin) {
                    for (0..step) |_| std.atomic.spinLoopHint();
                    spun += step;
                    step = @min(step * 2, 64);
                } else {
                    std.Thread.yield() catch {};
                }
            }
        }
        s.value = value;
        // Sequentially consistent, with the load of `sleeping` after it and
        // the receiver's store to `sleeping` and load of `seq` in park: one
        // side sees the other's store, so a receiver never sleeps on a
        // message nobody wakes it for.
        s.seq.store(t +% 1, .seq_cst);
        m.tail = t +% 1;
        if (m.sleeping.load(.seq_cst) != 0) io.futexWake(u32, &s.seq.raw, 1);
    }

    pub fn receive(m: *Mailbox, io: Io) i64 {
        const h = m.head;
        const s = &m.slots[h & m.mask];
        if (s.seq.load(.acquire) != h +% 1) m.park(io, s, h);
        const value = s.value;
        // Free for the sender's message one lap on.
        s.seq.store(h +% m.mask +% 1, .release);
        m.head = h +% 1;
        return value;
    }

    // The receiver found slot s empty (its sequence still h) and waits for
    // it to hold message h: spin, then sleep. It looks again after 1, 2,
    // 4, ... 64 pauses: each look pulls the line away from the sender.
    noinline fn park(m: *Mailbox, io: Io, s: *Slot, h: u32) void {
        var spun: u32 = 0;
        var step: u32 = 1;
        while (spun < m.spin) {
            for (0..step) |_| std.atomic.spinLoopHint();
            spun += step;
            step = @min(step * 2, 64);
            if (s.seq.load(.acquire) == h +% 1) return;
        }
        m.sleeping.store(1, .seq_cst);
        while (s.seq.load(.seq_cst) == h) io.futexWaitUncancelable(u32, &s.seq.raw, h);
        m.sleeping.store(0, .monotonic);
    }
};
