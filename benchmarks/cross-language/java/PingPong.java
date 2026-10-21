// Java ping-pong benchmark: two platform threads, each with a
// LinkedTransferQueue mailbox. Ping sends 0, 1, 2, ...; pong echoes each
// value back; ping checks it.
//
// Two units fit the cores, so platform threads, and LinkedTransferQueue,
// which spins briefly before it parks, as the C, C++, Rust and Zig mailboxes
// do (FAIRNESS.md, techniques). ArrayBlockingQueue parks at once and
// measured 18 times slower here.
import java.util.Locale;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedTransferQueue;

public class PingPong {
    private static int getMessages() {
        String env = System.getenv("BENCHMARK_MESSAGES");
        return env != null ? Integer.parseInt(env) : 100000;
    }
    private static final int MESSAGES = getMessages();

    public static void main(String[] args) throws InterruptedException {
        System.out.println("=== Java Ping-Pong Benchmark ===");
        System.out.println("Messages: " + MESSAGES);
        System.out.println("Using platform threads with LinkedTransferQueue mailboxes");
        System.out.println();

        // The sum of the values ping got back, which the runner checks.
        long[] checksum = {0};

        long start = System.nanoTime();

        BlockingQueue<Integer> toPong = new LinkedTransferQueue<>();
        BlockingQueue<Integer> toPing = new LinkedTransferQueue<>();

        Thread ping = new Thread(() -> {
            try {
                long sum = 0;
                for (int i = 0; i < MESSAGES; i++) {
                    toPong.put(i);
                    int received = toPing.take();
                    sum += received;
                    if (received != i) {
                        System.err.println("ERROR: Ping sent " + i + " but got back " + received);
                    }
                }
                checksum[0] = sum;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });
        Thread pong = new Thread(() -> {
            try {
                for (int i = 0; i < MESSAGES; i++) {
                    int received = toPong.take();
                    if (received != i) {
                        System.err.println("ERROR: Pong expected " + i + " but got " + received);
                    }
                    toPing.put(received);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });

        ping.start();
        pong.start();
        ping.join();
        pong.join();

        long totalNs = Math.max(System.nanoTime() - start, 1);

        System.out.println("Checksum: " + checksum[0]);
        // Locale.ROOT: the default locale prints "2,38" where it uses a
        // decimal comma, and the runner reads no rate from that.
        System.out.printf(Locale.ROOT, "ns/msg:         %.2f%n", (double) totalNs / MESSAGES);
        System.out.printf(Locale.ROOT, "Throughput:     %.2f M msg/sec%n", MESSAGES * 1000.0 / totalNs);
    }
}
