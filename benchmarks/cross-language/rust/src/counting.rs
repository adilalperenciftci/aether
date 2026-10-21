// Rust Counting Actor Benchmark (Savina-style)
// One counter thread receives N messages through its mailbox (mailbox.rs)
// and counts them; a final -1 tells it to stop.
mod mailbox;

use mailbox::Mailbox;
use std::thread;
use std::time::Instant;

// One unit fits the cores: spin, then sleep (FAIRNESS.md, techniques).
const SPIN: u32 = 1000;
// 1024 messages, the mailbox size of every language here that bounds one
// (FAIRNESS.md, techniques).
const CAPACITY: usize = 1024;

fn get_messages() -> usize {
    std::env::var("BENCHMARK_MESSAGES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100_000)
}

fn main() {
    let messages = get_messages();
    println!("=== Rust Counting Actor Benchmark ===");
    println!("Messages: {}\n", messages);

    let start = Instant::now();

    let inbox = Mailbox::new(CAPACITY, SPIN);
    // SAFETY, for every send and receive below: main is the only sender and
    // the counter the only receiver.
    let count = thread::scope(|s| {
        let counter = s.spawn(|| {
            let mut count = 0usize;
            while unsafe { inbox.receive() } >= 0 {
                count += 1;
            }
            count
        });
        for i in 0..messages as i64 {
            unsafe { inbox.send(i) };
        }
        unsafe { inbox.send(-1) };
        counter.join().unwrap()
    });

    let elapsed = start.elapsed().as_secs_f64().max(1e-9);

    if count != messages {
        println!("VALIDATION FAILED: expected {}, got {}", messages, count);
    }

    println!("Checksum: {}", count);
    println!("ns/msg:         {:.2}", elapsed * 1e9 / messages as f64);
    println!("Throughput:     {:.2} M msg/sec", messages as f64 / elapsed / 1e6);
}
