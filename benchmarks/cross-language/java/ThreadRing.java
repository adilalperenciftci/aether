// Java Thread Ring Benchmark (Savina-style)
// 100 virtual threads in a ring, each with an ArrayBlockingQueue mailbox,
// pass a token that counts down from the hop count; the node that receives
// 0 tells main.
//
// 100 units on fewer cores are oversubscribed: virtual threads, which park
// without an OS context switch, and ArrayBlockingQueue, which parks at once,
// as the C, C++, Rust and Zig rings block at once (FAIRNESS.md, techniques).
// Platform threads measured 5 times slower.
import java.util.Locale;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;

public class ThreadRing {
    private static final int RING_SIZE = 100;
    private static int getMessages() {
        String env = System.getenv("BENCHMARK_MESSAGES");
        return env != null ? Integer.parseInt(env) : 100000;
    }
    private static final int NUM_HOPS = getMessages();

    public static void main(String[] args) throws InterruptedException {
        System.out.println("=== Java Thread Ring Benchmark ===");
        System.out.println("Ring size: " + RING_SIZE + ", Hops: " + NUM_HOPS + "\n");

        // Tokens each node received; summed, the checksum. Read after join().
        long[] received = new long[RING_SIZE];

        long start = System.nanoTime();

        // One token in the ring, so a mailbox of one slot.
        @SuppressWarnings("unchecked")
        BlockingQueue<Integer>[] inbox = new BlockingQueue[RING_SIZE];
        for (int i = 0; i < RING_SIZE; i++) inbox[i] = new ArrayBlockingQueue<>(1);
        BlockingQueue<Integer> done = new ArrayBlockingQueue<>(1);

        Thread[] threads = new Thread[RING_SIZE];
        for (int i = 0; i < RING_SIZE; i++) {
            final int me = i;
            final BlockingQueue<Integer> next = inbox[(i + 1) % RING_SIZE];
            threads[i] = Thread.ofVirtual().start(() -> {
                try {
                    long count = 0;
                    for (;;) {
                        int token = inbox[me].take();
                        if (token < 0) break;      // main's stop, after the run
                        count++;
                        if (token == 0) done.put(0);
                        else next.put(token - 1);
                    }
                    received[me] = count;
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
        }

        inbox[0].put(NUM_HOPS);
        done.take();

        long totalNs = Math.max(System.nanoTime() - start, 1);

        // The token is spent and nothing sends any more: stop every node.
        for (int i = 0; i < RING_SIZE; i++) inbox[i].put(-1);
        long receipts = 0;
        for (int i = 0; i < RING_SIZE; i++) {
            threads[i].join();
            receipts += received[i];
        }

        long totalMessages = NUM_HOPS + 1;
        System.out.println("Checksum: " + receipts);
        System.out.printf(Locale.ROOT, "ns/msg:         %.2f%n", (double) totalNs / totalMessages);
        System.out.printf(Locale.ROOT, "Throughput:     %.2f M msg/sec%n", totalMessages * 1000.0 / totalNs);
    }
}
