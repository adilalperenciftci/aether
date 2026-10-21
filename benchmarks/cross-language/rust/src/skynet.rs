// Rust Skynet Benchmark
// Based on https://github.com/atemerev/skynet
// Uses std::thread while the subtree is larger than SEQ_THRESHOLD.
// Spawning 1M OS threads is not feasible; this limits concurrent threads to ~1000.

use std::sync::mpsc::{channel, Sender};
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

fn skynet(tx: Sender<i64>, offset: i64, size: i64, depth: usize) {
    if size <= SEQ_THRESHOLD {
        tx.send(skynet_seq(offset, size)).unwrap();
        return;
    }
    let child_size = size / 10;
    let (child_tx, child_rx) = channel::<i64>();
    for i in 0..10i64 {
        let child_offset = offset + i * child_size;
        let child_tx = child_tx.clone();
        thread::spawn(move || {
            skynet(child_tx, child_offset, child_size, depth + 1);
        });
    }
    let mut sum = 0i64;
    for _ in 0..10 {
        sum += child_rx.recv().unwrap();
    }
    tx.send(sum).unwrap();
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

    let (tx, rx) = channel::<i64>();
    let start = Instant::now();
    thread::spawn(move || skynet(tx, 0, num_leaves, 0));
    let sum = rx.recv().unwrap();
    let elapsed = start.elapsed();

    let elapsed_ns = (elapsed.as_nanos() as i64).max(1);

    println!("Sum: {}", sum);
    println!("Checksum: {}", sum);
    // Always printed: a tree small enough to finish within a microsecond
    // printed no rate at all, which the runner reads as a broken run.
    println!("ns/msg:         {}", elapsed_ns / total_actors);
    println!("Throughput:     {:.2} M msg/sec", total_actors as f64 * 1000.0 / elapsed_ns as f64);
}
