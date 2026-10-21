package bench.thread_ring

import java.util.Locale
import java.util.concurrent.{ArrayBlockingQueue, CountDownLatch}

// 100 threads in a ring, each passing the token to the next. The node that
// receives 0 ends the run, as in every other language here: hops + 1
// messages in all. (The token used to travel on round the ring after 0, up
// to 99 more messages than the rate divided by.) 100 units on fewer cores
// are oversubscribed: virtual threads, which park without an OS context
// switch, and ArrayBlockingQueue, which parks at once, as Java does
// (FAIRNESS.md, techniques).
object ThreadRingBenchmark {
  def main(args: Array[String]): Unit = {
    val messages = sys.env.getOrElse("BENCHMARK_MESSAGES", "1000000").toLong
    val ringSize = 100

    println("=== Scala Thread Ring Benchmark ===")
    println(s"Ring size: $ringSize, messages: $messages")
    println("Using virtual threads with ArrayBlockingQueue mailboxes\n")

    val queues = Array.fill(ringSize)(new ArrayBlockingQueue[java.lang.Long](1))
    val threads = new Array[Thread](ringSize)
    // Tokens each node received; summed, the checksum. Each count is written
    // before the node passes the token on, so the queues order every one of
    // them before the countDown the main thread waits for.
    val received = new Array[Long](ringSize)
    val done = new CountDownLatch(1)

    val start = System.nanoTime()

    var id = 0
    while (id < ringSize) {
      val me = id
      val next = (id + 1) % ringSize
      threads(me) = Thread.ofVirtual().unstarted(() => {
        try {
          while (true) {
            val token = queues(me).take().longValue()
            received(me) += 1
            if (token == 0) done.countDown()
            else queues(next).put(java.lang.Long.valueOf(token - 1))
          }
        } catch {
          case _: InterruptedException => ()
        }
      })
      threads(me).start()
      id += 1
    }

    queues(0).put(java.lang.Long.valueOf(messages))
    done.await()

    val elapsed = math.max(System.nanoTime() - start, 1L)
    val total = messages + 1
    val nsPerMsg = elapsed / total
    val throughput = total.toDouble / elapsed * 1e9

    println(s"Checksum: ${received.sum}")
    println(s"ns/msg:         $nsPerMsg")
    println("Throughput:     %.2f M msg/sec".formatLocal(Locale.ROOT, throughput / 1e6))

    var t = 0
    while (t < ringSize) { threads(t).interrupt(); t += 1 }
  }
}
