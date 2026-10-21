// Rust ping-pong benchmark: two std threads, each with a mailbox
// (mailbox.rs). Ping sends 0, 1, 2, ...; pong echoes each value back; ping
// checks it.
mod mailbox;

use mailbox::Mailbox;
use std::thread;
use std::time::Instant;

// Two units fit the cores: spin, then sleep (FAIRNESS.md, techniques).
const SPIN: u32 = 1000;

fn get_messages() -> usize {
    std::env::var("BENCHMARK_MESSAGES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100_000)
}

fn main() {
    let messages = get_messages();
    println!("=== Rust Ping-Pong Benchmark ===");
    println!("Messages: {}", messages);
    println!("Using std::thread with std-atomic mailboxes (spin, then sleep)\n");

    let start = Instant::now();

    // One message in flight each way, so a mailbox of one slot.
    let to_ping = Mailbox::new(1, SPIN);
    let to_pong = Mailbox::new(1, SPIN);

    // Ping returns the sum of the values it got back, which the runner checks.
    // SAFETY, for every send and receive below: ping is the only sender to
    // pong and the only receiver from it, and pong the reverse.
    let checksum = thread::scope(|s| {
        let ping = s.spawn(|| {
            let mut checksum = 0i64;
            for i in 0..messages as i64 {
                unsafe { to_pong.send(i) };
                let received = unsafe { to_ping.receive() };
                checksum += received;
                if received != i {
                    eprintln!("ERROR: Ping sent {} but got back {}", i, received);
                }
            }
            checksum
        });
        s.spawn(|| {
            for expected in 0..messages as i64 {
                let received = unsafe { to_pong.receive() };
                if received != expected {
                    eprintln!("ERROR: Pong expected {} but got {}", expected, received);
                }
                unsafe { to_ping.send(received) };
            }
        });
        ping.join().unwrap()
    });

    let elapsed = start.elapsed().as_secs_f64().max(1e-9);

    println!("Checksum: {}", checksum);
    println!("ns/msg:         {:.2}", elapsed * 1e9 / messages as f64);
    println!("Throughput:     {:.2} M msg/sec", messages as f64 / elapsed / 1e6);
}
