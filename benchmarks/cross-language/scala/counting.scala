package bench.counting

import java.util.concurrent.ArrayBlockingQueue

// Single consumer draining a bounded queue: the standard-library equivalent of
// one actor with a mailbox.
object CountingBenchmark {
  def main(args: Array[String]): Unit = {
    val messages = sys.env.getOrElse("BENCHMARK_MESSAGES", "1000000").toLong

    println("=== Scala Counting Benchmark ===")
    println(s"Messages: $messages")
    println("Using java.util.concurrent.ArrayBlockingQueue\n")

    val queue = new ArrayBlockingQueue[java.lang.Long](1024)
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

    val elapsed = System.nanoTime() - start
    val nsPerMsg = elapsed / received
    val throughput = received.toDouble / elapsed * 1e9

    println(s"Checksum: $received")
    println(s"ns/msg:         $nsPerMsg")
    println(f"Throughput:     ${throughput / 1e6}%.2f M msg/sec")
  }
}
