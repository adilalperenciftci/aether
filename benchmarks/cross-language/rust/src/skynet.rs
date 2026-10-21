// Rust Skynet Benchmark
// Based on https://github.com/atemerev/skynet
// Uses std::thread while the subtree is larger than SEQ_THRESHOLD.
// Spawning 1M OS threads is not feasible; this limits concurrent threads to ~1000.
//
// Each node joins its ten children and sums what they return, as C, C++ and
// Zig do: 1,111 threads on fewer cores are oversubscribed, and a join blocks
// at once (FAIRNESS.md, techniques). It used to gather the sums over an mpsc
// channel, whose receive spins and yields before it sleeps.

use std::thread;
use std::time::Instant;

fn get_leaves() -> i64 {
    if let Ok(s) = std::env::var("SKYNET_LEAVES") {
        if let Ok(n) = s.parse() {
            return n;
        }
    }
    if let Ok(s) = std::env::var("BENCHMARK_MESSAGES") {
        if let Ok(n) = s.parse() {
            return n;
        }
    }
    1_000_000
}

// Same threshold in every language here; divisor is the unit count, not the
// tree's nodes. See FAIRNESS.md.
const SEQ_THRESHOLD: i64 = 1000;

fn skynet_seq(offset: i64, size: i64) -> i64 {
    let mut sum = 0i64;
    for i in 0..size {
        sum += offset + i;
    }
    sum
}

fn skynet(offset: i64, size: i64) -> i64 {
    if size <= SEQ_THRESHOLD {
        return skynet_seq(offset, size);
    }
    let child_size = size / 10;
    let children: Vec<_> = (0..10i64)
        .map(|i| thread::spawn(move || skynet(offset + i * child_size, child_size)))
        .collect();
    children.into_iter().map(|h| h.join().unwrap()).sum()
}

fn main() {
    let num_leaves = get_leaves();

    // Units created; also the divisor. See FAIRNESS.md.
    let mut total_actors = 1i64;
    let mut n = num_leaves;
    while n > SEQ_THRESHOLD {
        total_actors += n / SEQ_THRESHOLD;
        n /= 10;
    }

    println!("=== Rust Skynet Benchmark ===");
    println!("Leaves: {}, concurrency units: {} (sequential below {})\n", num_leaves, total_actors, SEQ_THRESHOLD);

    let start = Instant::now();
    let sum = thread::spawn(move || skynet(0, num_leaves)).join().unwrap();
    let elapsed = start.elapsed();

    let elapsed_ns = (elapsed.as_nanos() as i64).max(1);

    println!("Sum: {}", sum);
    println!("Checksum: {}", sum);
    // Always printed: a tree small enough to finish within a microsecond
    // printed no rate at all, which the runner reads as a broken run.
    println!("ns/msg:         {}", elapsed_ns / total_actors);
    println!("Throughput:     {:.2} M msg/sec", total_actors as f64 * 1000.0 / elapsed_ns as f64);
}
