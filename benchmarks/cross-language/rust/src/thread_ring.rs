// Rust Thread Ring Benchmark (Savina-style)
// 100 std threads in a ring, each with a mailbox (mailbox.rs), pass a token
// that counts down from the hop count; the node that receives 0 tells main.
mod mailbox;

use mailbox::Mailbox;
use std::thread;
use std::time::Instant;

const RING_SIZE: usize = 100;
// No spinning: a node waits about 99 hops for the token, and 100 spinning
// threads on fewer cores take the CPU from the one thread that holds it
// (FAIRNESS.md, techniques).
const SPIN: u32 = 0;

fn get_messages() -> usize {
    std::env::var("BENCHMARK_MESSAGES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100_000)
}

fn main() {
    let num_hops = get_messages();
    println!("=== Rust Thread Ring Benchmark ===");
    println!("Ring size: {}, Hops: {}\n", RING_SIZE, num_hops);

    let start = Instant::now();

    // One token in the ring, so a mailbox of one slot.
    let inbox: Vec<Mailbox> = (0..RING_SIZE).map(|_| Mailbox::new(1, SPIN)).collect();
    let done = Mailbox::new(1, SPIN); // main's: the node that gets 0 writes here

    // SAFETY, for every send and receive below: each node is its inbox's only
    // receiver; its only sender is the node before it, except main's first
    // token and its stops, which the token orders before and after every
    // node's sends. Main is done's only receiver, the node that gets 0 its
    // only sender.
    let (elapsed, receipts) = thread::scope(|s| {
        let nodes: Vec<_> = (0..RING_SIZE)
            .map(|id| {
                let (me, next, done) = (&inbox[id], &inbox[(id + 1) % RING_SIZE], &done);
                s.spawn(move || {
                    let mut received = 0usize;
                    loop {
                        let token = unsafe { me.receive() };
                        if token < 0 {
                            break; // main's stop, after the run
                        }
                        received += 1;
                        if token == 0 {
                            unsafe { done.send(0) };
                        } else {
                            unsafe { next.send(token - 1) };
                        }
                    }
                    received
                })
            })
            .collect();

        unsafe { inbox[0].send(num_hops as i64) };
        unsafe { done.receive() };
        let elapsed = start.elapsed().as_secs_f64().max(1e-9);

        // The token is spent and nothing sends any more: stop every node, and
        // sum what each received, the checksum.
        for m in &inbox {
            unsafe { m.send(-1) };
        }
        let receipts: usize = nodes.into_iter().map(|h| h.join().unwrap()).sum();
        (elapsed, receipts)
    });

    let total_messages = num_hops + 1;
    println!("Checksum: {}", receipts);
    println!("ns/msg:         {:.2}", elapsed * 1e9 / total_messages as f64);
    println!("Throughput:     {:.2} M msg/sec", total_messages as f64 / elapsed / 1e6);
}
