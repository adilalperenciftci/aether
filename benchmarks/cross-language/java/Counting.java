// Java Counting Actor Benchmark (Savina-style)
// One counter thread receives N messages through its LinkedTransferQueue
// mailbox and counts them; a final -1 tells it to stop.
//
// One unit fits the cores: a platform thread, and LinkedTransferQueue, which
// spins briefly before it parks (FAIRNESS.md, techniques).
import java.util.Locale;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedTransferQueue;

public class Counting {
    private static int getMessages() {
        String env = System.getenv("BENCHMARK_MESSAGES");
        return env != null ? Integer.parseInt(env) : 100000;
    }
    private static final int MESSAGES = getMessages();

    public static void main(String[] args) throws InterruptedException {
        System.out.println("=== Java Counting Actor Benchmark ===");
        System.out.println("Messages: " + MESSAGES + "\n");

        // The messages the counter took, the checksum; read after join().
        long[] count = {0};

        long start = System.nanoTime();

        BlockingQueue<Integer> queue = new LinkedTransferQueue<>();
        Thread counter = new Thread(() -> {
            try {
                long n = 0;
                while (queue.take() >= 0) n++;
                count[0] = n;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });
        counter.start();

        for (int i = 0; i < MESSAGES; i++) {
            queue.put(i);
        }
        queue.put(-1);

        counter.join();

        long totalNs = Math.max(System.nanoTime() - start, 1);

        if (count[0] != MESSAGES) {
            System.out.println("VALIDATION FAILED: expected " + MESSAGES + ", got " + count[0]);
        }

        System.out.println("Checksum: " + count[0]);
        System.out.printf(Locale.ROOT, "ns/msg:         %.2f%n", (double) totalNs / MESSAGES);
        System.out.printf(Locale.ROOT, "Throughput:     %.2f M msg/sec%n", MESSAGES * 1000.0 / totalNs);
    }
}
