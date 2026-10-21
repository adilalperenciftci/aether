package bench.counting

import java.util.Locale
import java.util.concurrent.LinkedTransferQueue

// Single consumer draining its queue: the standard-library equivalent of one
// actor with a mailbox. One unit fits the cores: a platform thread, and
// LinkedTransferQueue, which spins briefly before it parks, as Java does
// (FAIRNESS.md, techniques).
object CountingBenchmark {
  def main(args: Array[String]): Unit = {
    val messages = sys.env.getOrElse("BENCHMARK_MESSAGES", "1000000").toLong

    println("=== Scala Counting Benchmark ===")
    println(s"Messages: $messages")
    println("Using a platform thread with a LinkedTransferQueue mailbox\n")

    val queue = new LinkedTransferQueue[java.lang.Long]()
    // The count the consumer reaches, the checksum; read after join().
    val counted = new Array[Long](1)

    val start = System.nanoTime()

    val consumer = new Thread(() => {
      var seen = 0L
      while (seen < messages) {
        queue.take()
        seen += 1
      }
      counted(0) = seen
    })
    consumer.start()

    var i = 0L
    while (i < messages) {
      queue.put(java.lang.Long.valueOf(i))
      i += 1
    }
    consumer.join()
    val received = counted(0)

    val elapsed = math.max(System.nanoTime() - start, 1L)
    val nsPerMsg = elapsed / received
    val throughput = received.toDouble / elapsed * 1e9

    println(s"Checksum: $received")
    println(s"ns/msg:         $nsPerMsg")
    println("Throughput:     %.2f M msg/sec".formatLocal(Locale.ROOT, throughput / 1e6))
  }
}
