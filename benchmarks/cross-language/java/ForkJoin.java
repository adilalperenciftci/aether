// Java Fork-Join Benchmark (Savina-style)
// 8 platform worker threads, each with a LinkedTransferQueue mailbox; main
// sends the messages round-robin, then a -1 to each, and joins them.
//
// 8 units fit the cores: platform threads, and LinkedTransferQueue, which
// spins briefly before it parks (FAIRNESS.md, techniques).
// ArrayBlockingQueue parks at once and measured 12 times slower here.
import java.util.Locale;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedTransferQueue;

public class ForkJoin {
    private static final int NUM_WORKERS = 8;
    private static int getMessagesPerWorker() {
        String env = System.getenv("BENCHMARK_MESSAGES");
        int total = env != null ? Integer.parseInt(env) : 100000;
        return total / NUM_WORKERS;
    }
    private static final int MESSAGES_PER_WORKER = getMessagesPerWorker();

    public static void main(String[] args) throws InterruptedException {
        int total = NUM_WORKERS * MESSAGES_PER_WORKER;
        System.out.println("=== Java Fork-Join Throughput Benchmark ===");
        System.out.println("Workers: " + NUM_WORKERS + ", Messages: " + total + "\n");

        // What each worker took and the sum of the values; read after join().
        long[] processed = new long[NUM_WORKERS];
        long[] sums = new long[NUM_WORKERS];

        long start = System.nanoTime();

        @SuppressWarnings("unchecked")
        BlockingQueue<Integer>[] inbox = new BlockingQueue[NUM_WORKERS];
        Thread[] threads = new Thread[NUM_WORKERS];
        for (int i = 0; i < NUM_WORKERS; i++) {
            final int me = i;
            inbox[i] = new LinkedTransferQueue<>();
            threads[i] = new Thread(() -> {
                try {
                    long n = 0, sum = 0;
                    for (;;) {
                        int value = inbox[me].take();
                        if (value < 0) break;
                        sum += value;
                        n++;
                    }
                    processed[me] = n;
                    sums[me] = sum;
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            });
            threads[i].start();
        }

        // Send messages round-robin
        for (int i = 0; i < total; i++) {
            inbox[i % NUM_WORKERS].put(i);
        }
        for (int i = 0; i < NUM_WORKERS; i++) {
            inbox[i].put(-1);
        }
        for (int i = 0; i < NUM_WORKERS; i++) {
            threads[i].join();
        }

        long totalNs = Math.max(System.nanoTime() - start, 1);

        long totalProcessed = 0;
        long checksum = 0;
        for (int i = 0; i < NUM_WORKERS; i++) {
            totalProcessed += processed[i];
            checksum += sums[i];
        }
        if (totalProcessed != total) {
            System.out.println("VALIDATION FAILED: expected " + total + ", got " + totalProcessed);
        }

        System.out.println("Checksum: " + checksum);
        System.out.printf(Locale.ROOT, "ns/msg:         %.2f%n", (double) totalNs / total);
        System.out.printf(Locale.ROOT, "Throughput:     %.2f M msg/sec%n", total * 1000.0 / totalNs);
    }
}
