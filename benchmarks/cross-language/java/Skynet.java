// Java Skynet Benchmark
// Based on https://github.com/atemerev/skynet
// Uses ForkJoinPool for recursive parallel decomposition.
// Below the sequential threshold, subtree sums are computed without forking.

import java.util.Locale;
import java.util.concurrent.ForkJoinPool;
import java.util.concurrent.RecursiveTask;

public class Skynet {
    private static final int SEQ_THRESHOLD = 1000;

    static class SkynetTask extends RecursiveTask<Long> {
        private final long offset;
        private final long size;

        SkynetTask(long offset, long size) {
            this.offset = offset;
            this.size = size;
        }

        @Override
        protected Long compute() {
            if (size <= SEQ_THRESHOLD) {
                long sum = 0;
                for (long i = 0; i < size; i++) {
                    sum += offset + i;
                }
                return sum;
            }

            long childSize = size / 10;
            long remainder = size - childSize * 10;
            SkynetTask[] children = new SkynetTask[10];
            long childOffset = offset;

            for (int i = 0; i < 10; i++) {
                long cs = childSize + (i < remainder ? 1 : 0);
                children[i] = new SkynetTask(childOffset, cs);
                childOffset += cs;
            }

            for (int i = 1; i < 10; i++) {
                children[i].fork();
            }

            long sum = children[0].compute();
            for (int i = 1; i < 10; i++) {
                sum += children[i].join();
            }
            return sum;
        }
    }

    public static void main(String[] args) {
        String env = System.getenv("BENCHMARK_MESSAGES");
        long numLeaves = env != null ? Long.parseLong(env) : 1000000;

        // Units created; also the divisor. See FAIRNESS.md.
        long totalNodes = 1;
        for (long n = numLeaves; n > SEQ_THRESHOLD; n /= 10) totalNodes += n / SEQ_THRESHOLD;

        // The clock starts before the pool exists, as in every language here
        // (FAIRNESS.md, rule 5).
        long start = System.nanoTime();
        ForkJoinPool pool = new ForkJoinPool();
        long result = pool.invoke(new SkynetTask(0, numLeaves));
        long elapsed = Math.max(System.nanoTime() - start, 1);

        System.out.println("Leaves: " + numLeaves + ", concurrency units: " + totalNodes
                + " (sequential below " + SEQ_THRESHOLD + ")");
        System.out.println("Sum: " + result);
        System.out.println("Checksum: " + result);

        // Always printed, as in every language here: a tree small enough to
        // finish within a microsecond printed no rate at all.
        System.out.println("ns/msg:         " + elapsed / totalNodes);
        System.out.printf(Locale.ROOT, "Throughput:     %.2f M msg/sec%n", totalNodes * 1000.0 / elapsed);

        pool.shutdown();
    }
}
