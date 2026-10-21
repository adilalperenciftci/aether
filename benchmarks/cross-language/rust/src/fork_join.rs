// Rust Fork-Join Benchmark (Savina-style)
// 8 worker std threads, each with a mailbox (mailbox.rs); main sends the
// messages round-robin, then a -1 to each, and joins them.
mod mailbox;

use mailbox::Mailbox;
use std::thread;
use std::time::Instant;

const NUM_WORKERS: usize = 8;
// 8 units fit the cores: spin, then sleep (FAIRNESS.md, techniques).
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
    // An equal share for each worker, as in every other language here.
    let total = get_messages() / NUM_WORKERS * NUM_WORKERS;
    println!("=== Rust Fork-Join Throughput Benchmark ===");
    println!("Workers: {}, Messages: {}\n", NUM_WORKERS, total);

    let start = Instant::now();

    let inbox: Vec<Mailbox> = (0..NUM_WORKERS).map(|_| Mailbox::new(CAPACITY, SPIN)).collect();

    // SAFETY, for every send and receive below: main is each mailbox's only
    // sender and its worker the only receiver.
    let (total_processed, checksum) = thread::scope(|s| {
        let workers: Vec<_> = inbox
            .iter()
            .map(|me| {
                s.spawn(move || {
                    // The messages this worker took and the sum of their values.
                    let (mut count, mut sum) = (0usize, 0i64);
                    loop {
                        let value = unsafe { me.receive() };
                        if value < 0 {
                            break;
                        }
                        sum += value;
                        count += 1;
                    }
                    (count, sum)
                })
            })
            .collect();

        for i in 0..total {
            unsafe { inbox[i % NUM_WORKERS].send(i as i64) };
        }
        for m in &inbox {
            unsafe { m.send(-1) };
        }
        workers.into_iter().map(|h| h.join().unwrap()).fold((0, 0), |(c, s), (n, v)| (c + n, s + v))
    });

    let elapsed = start.elapsed().as_secs_f64().max(1e-9);

    if total_processed != total {
        println!("VALIDATION FAILED: expected {}, got {}", total, total_processed);
    }

    println!("Checksum: {}", checksum);
    println!("ns/msg:         {:.2}", elapsed * 1e9 / total as f64);
    println!("Throughput:     {:.2} M msg/sec", total as f64 / elapsed / 1e6);
}
