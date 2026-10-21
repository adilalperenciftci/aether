// A mailbox for one sending thread and one receiving thread on std atomics,
// the same design as c/mailbox.h: a bounded ring with a sequence number in
// each slot, so neither side reads the other's index and a message moves the
// cache line of its slot and nothing else. A receiver that finds its slot
// empty spins up to `spin` pauses, looking again after 1, 2, 4, ... 64 of
// them, then sleeps on a std Condvar; a sender that finds its slot full
// spins, then yields.
//
// Rust's std has channels too (std::sync::mpsc), and FAIRNESS.md records
// how they measured against this; the patterns here have one sender per
// mailbox, the shape this ring is for.

use std::cell::{Cell, UnsafeCell};
use std::hint::spin_loop;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};

#[repr(align(64))]
struct Line<T>(T);

struct Slot {
    // i: free for the sender's i-th message; i + 1: holds it.
    seq: AtomicU64,
    value: UnsafeCell<i64>,
}

pub struct Mailbox {
    head: Line<Cell<u64>>, // the receiver's next message
    tail: Line<Cell<u64>>, // the sender's next message
    sleeping: Line<AtomicBool>,
    lock: Mutex<()>,
    wake: Condvar,
    mask: u64,
    spin: u32,
    slots: Box<[Slot]>,
}

// One thread sends and one receives at a time, and a change of sender is
// ordered by the messages themselves (see send and receive).
unsafe impl Sync for Mailbox {}

impl Mailbox {
    /// capacity: a power of two. spin: the pauses a receiver spends
    /// before it sleeps.
    pub fn new(capacity: usize, spin: u32) -> Mailbox {
        Mailbox {
            head: Line(Cell::new(0)),
            tail: Line(Cell::new(0)),
            sleeping: Line(AtomicBool::new(false)),
            lock: Mutex::new(()),
            wake: Condvar::new(),
            mask: capacity as u64 - 1,
            spin,
            slots: (0..capacity as u64)
                .map(|i| Slot { seq: AtomicU64::new(i), value: UnsafeCell::new(0) })
                .collect(),
        }
    }

    /// # Safety
    /// Only one thread sends at a time, and the next sender's first send
    /// happens after the previous sender's last one.
    pub unsafe fn send(&self, value: i64) {
        let t = self.tail.0.get();
        let s = &self.slots[(t & self.mask) as usize];
        if s.seq.load(Ordering::Acquire) != t {
            let (mut spun, mut step) = (0, 1);
            while s.seq.load(Ordering::Acquire) != t {
                if spun < self.spin {
                    for _ in 0..step {
                        spin_loop();
                    }
                    spun += step;
                    step = (step * 2).min(64);
                } else {
                    std::thread::yield_now();
                }
            }
        }
        *s.value.get() = value;
        // SeqCst with the load of `sleeping` after it, and the receiver's
        // store to `sleeping` and load of `seq` in park: one side sees the
        // other's store, so a receiver never sleeps on a message.
        s.seq.store(t + 1, Ordering::SeqCst);
        self.tail.0.set(t + 1);
        if self.sleeping.0.load(Ordering::SeqCst) {
            let _guard = self.lock.lock().unwrap();
            self.wake.notify_one();
        }
    }

    /// # Safety
    /// Only one thread receives.
    pub unsafe fn receive(&self) -> i64 {
        let h = self.head.0.get();
        let s = &self.slots[(h & self.mask) as usize];
        if s.seq.load(Ordering::Acquire) != h + 1 {
            self.park(s, h + 1);
        }
        let value = *s.value.get();
        // Free for the sender's message one lap on.
        s.seq.store(h + self.mask + 1, Ordering::Release);
        self.head.0.set(h + 1);
        value
    }

    // The receiver found slot s empty and waits for its sequence to be
    // `full`: spin, then sleep. It looks again after 1, 2, 4, ... 64 pauses:
    // each look pulls the slot's cache line away from the sender.
    #[inline(never)]
    fn park(&self, s: &Slot, full: u64) {
        let (mut spun, mut step) = (0, 1);
        while spun < self.spin {
            for _ in 0..step {
                spin_loop();
            }
            spun += step;
            step = (step * 2).min(64);
            if s.seq.load(Ordering::Acquire) == full {
                return;
            }
        }
        let mut guard = self.lock.lock().unwrap();
        self.sleeping.0.store(true, Ordering::SeqCst);
        while s.seq.load(Ordering::SeqCst) != full {
            guard = self.wake.wait(guard).unwrap();
        }
        self.sleeping.0.store(false, Ordering::Relaxed);
    }
}
