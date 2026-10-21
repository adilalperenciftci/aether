// Rust Thread Ring Benchmark (Savina-style)
use std::sync::mpsc::{channel, Sender, Receiver};
use std::thread;
use std::time::Instant;

const RING_SIZE: usize = 100;

fn get_messages() -> usize {
    std::env::var("BENCHMARK_MESSAGES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100_000)
}

// Passes the token on until it reaches 0, then signals done. Returns how many
// tokens it received: the receipts summed over the ring are the checksum.
// The node that saw 0 returns at once, dropping its sender to the next node,
// whose inbox then closes, and so on round the ring.
fn ring_node(rx: Receiver<usize>, next_tx: Sender<usize>, done_tx: Sender<()>) -> usize {
    let mut received = 0;
    while let Ok(token) = rx.recv() {
        received += 1;
        if token == 0 {
            done_tx.send(()).unwrap();
            return received;
        }
        next_tx.send(token - 1).unwrap();
    }
    received
}

fn main() {
    let num_hops = get_messages();
    println!("=== Rust Thread Ring Benchmark ===");
    println!("Ring size: {}, Hops: {}\n", RING_SIZE, num_hops);

    let (done_tx, done_rx) = channel();

    // Create channels for the ring
    let mut senders: Vec<Sender<usize>> = Vec::with_capacity(RING_SIZE);
    let mut receivers: Vec<Receiver<usize>> = Vec::with_capacity(RING_SIZE);

    for _ in 0..RING_SIZE {
        let (tx, rx) = channel();
        senders.push(tx);
        receivers.push(rx);
    }

    // Start threads
    let mut handles = Vec::with_capacity(RING_SIZE);
    for i in 0..RING_SIZE {
        let rx = receivers.remove(0);
        let next_tx = senders[(i + 1) % RING_SIZE].clone();
        let done = done_tx.clone();
        handles.push(thread::spawn(move || ring_node(rx, next_tx, done)));
    }
    drop(done_tx);

    let start = Instant::now();

    // Inject token
    senders[0].send(num_hops).unwrap();

    // Wait for completion
    done_rx.recv().unwrap();

    let elapsed = start.elapsed().as_secs_f64();

    // Cleanup - drop senders to unblock threads, and sum their receipts
    drop(senders);
    let mut receipts = 0usize;
    for h in handles {
        receipts += h.join().unwrap();
    }

    let total_messages = num_hops + 1;
    let throughput = total_messages as f64 / elapsed / 1e6;
    let ns_per_msg = elapsed * 1e9 / total_messages as f64;

    println!("Checksum: {}", receipts);
    println!("ns/msg:         {:.2}", ns_per_msg);
    println!("Throughput:     {:.2} M msg/sec", throughput);
}
