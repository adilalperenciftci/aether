// Go Thread Ring Benchmark (Savina-style)
// Uses buffered channels to model actor mailboxes
package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

func getMessages() int {
	if env := os.Getenv("BENCHMARK_MESSAGES"); env != "" {
		if n, err := strconv.Atoi(env); err == nil {
			return n
		}
	}
	return 100000
}

// Match other implementations: 100 nodes, configurable hops
const ringSize = 100

var numHops = getMessages()

// ringNode passes the token on until it reaches 0, then signals done and
// keeps its inbox open; when main closes the inboxes it reports how many
// tokens it received, so the receipts summed over the ring are the checksum.
func ringNode(inbox <-chan int, next chan<- int, done chan<- struct{}, counts chan<- int) {
	received := 0
	for token := range inbox {
		received++
		if token == 0 {
			done <- struct{}{}
			continue
		}
		next <- token - 1
	}
	counts <- received
}

func main() {
	fmt.Println("=== Go Thread Ring Benchmark ===")
	fmt.Printf("Ring size: %d, Hops: %d\n\n", ringSize, numHops)

	// The clock starts before the nodes exist, as in every language here
	// (FAIRNESS.md, rule 5).
	start := time.Now()

	// Buffered channels model actor mailboxes: a send does not wait for the
	// receiver. One token is in the ring, so one slot is enough.
	channels := make([]chan int, ringSize)
	for i := 0; i < ringSize; i++ {
		channels[i] = make(chan int, 1)
	}

	done := make(chan struct{})
	counts := make(chan int, ringSize)

	// Start goroutines
	for i := 0; i < ringSize; i++ {
		next := channels[(i+1)%ringSize]
		go ringNode(channels[i], next, done, counts)
	}

	// Inject initial token
	channels[0] <- numHops

	// Wait for completion
	<-done

	elapsed := time.Since(start)

	// The token is spent, so nothing sends any more: close the inboxes and
	// sum what every node received.
	for i := 0; i < ringSize; i++ {
		close(channels[i])
	}
	receipts := 0
	for i := 0; i < ringSize; i++ {
		receipts += <-counts
	}

	totalMessages := numHops + 1
	elapsedSec := elapsed.Seconds()
	throughput := float64(totalMessages) / elapsedSec / 1e6
	nsPerMsg := elapsedSec * 1e9 / float64(totalMessages)

	fmt.Printf("Checksum: %d\n", receipts)
	fmt.Printf("ns/msg:         %.2f\n", nsPerMsg)
	fmt.Printf("Throughput:     %.2f M msg/sec\n", throughput)
}
