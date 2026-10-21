package bench.ping_pong

import java.util.Locale
import java.util.concurrent.LinkedTransferQueue

// Two threads exchanging one value at a time in each direction: a strict
// request-response round trip, as in the other implementations. Two units
// fit the cores: platform threads, and LinkedTransferQueue, which spins
// briefly before it parks, as Java does (FAIRNESS.md, techniques).
object PingPongBenchmark {
  def main(args: Array[String]): Unit = {
    val messages = sys.env.getOrElse("BENCHMARK_MESSAGES", "1000000").toLong

    println("=== Scala Ping-Pong Benchmark ===")
    println(s"Messages: $messages")
    println("Using platform threads with LinkedTransferQueue mailboxes\n")

    val toPong = new LinkedTransferQueue[java.lang.Long]()
    val toPing = new LinkedTransferQueue[java.lang.Long]()
    @volatile var errors = 0L
    // The sum of the values ping got back, which the runner checks.
    var checksum = 0L

    val start = System.nanoTime()

    val pong = new Thread(() => {
      var n = 0L
      while (n < messages) {
        val v = toPong.take()
        toPing.put(v)
        n += 1
      }
    })
    pong.start()

    var i = 0L
    while (i < messages) {
      toPong.put(java.lang.Long.valueOf(i))
      val back = toPing.take()
      checksum += back.longValue()
      if (back.longValue() != i) errors += 1
      i += 1
    }
    pong.join()

    val elapsed = math.max(System.nanoTime() - start, 1L)
    if (errors > 0) println(s"VALIDATION FAILED: $errors errors")

    val nsPerMsg = elapsed / messages
    val throughput = messages.toDouble / elapsed * 1e9

    println(s"Checksum: $checksum")
    println(s"ns/msg:         $nsPerMsg")
    println("Throughput:     %.2f M msg/sec".formatLocal(Locale.ROOT, throughput / 1e6))
  }
}
