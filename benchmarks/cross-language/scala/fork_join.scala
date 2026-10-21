package bench.fork_join

import java.util.Locale
import java.util.concurrent.{CountDownLatch, LinkedTransferQueue}

// Fan-out to 8 workers, each draining its own queue. 8 units fit the cores:
// platform threads, and LinkedTransferQueue, which spins briefly before it
// parks, as Java does (FAIRNESS.md, techniques).
object ForkJoinBenchmark {
  def main(args: Array[String]): Unit = {
    val messages = sys.env.getOrElse("BENCHMARK_MESSAGES", "1000000").toLong
    val workers = 8
    val perWorker = messages / workers
    val total = perWorker * workers

    println("=== Scala Fork-Join Benchmark ===")
    println(s"Workers: $workers, messages: $total")
    println("Using platform threads with LinkedTransferQueue mailboxes\n")

    val queues = Array.fill(workers)(new LinkedTransferQueue[java.lang.Long]())
    val done = new CountDownLatch(workers)
    // The values each worker received; summed, the checksum.
    val sums = new Array[Long](workers)

    val start = System.nanoTime()

    var w = 0
    while (w < workers) {
      val me = w
      new Thread(() => {
        var seen = 0L
        var sum = 0L
        while (seen < perWorker) {
          sum += queues(me).take().longValue()
          seen += 1
        }
        sums(me) = sum
        done.countDown()
      }).start()
      w += 1
    }

    // Round-robin: message m goes to worker m % workers, its value m, as in
    // every other language here.
    var i = 0L
    while (i < perWorker) {
      var k = 0
      while (k < workers) {
        queues(k).put(java.lang.Long.valueOf(i * workers + k))
        k += 1
      }
      i += 1
    }
    done.await()

    val elapsed = math.max(System.nanoTime() - start, 1L)
    val nsPerMsg = elapsed / total
    val throughput = total.toDouble / elapsed * 1e9

    println(s"Checksum: ${sums.sum}")
    println(s"ns/msg:         $nsPerMsg")
    println("Throughput:     %.2f M msg/sec".formatLocal(Locale.ROOT, throughput / 1e6))
  }
}
