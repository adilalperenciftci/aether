// Go Fork-Join Benchmark (Savina-style)
package main

import (
	"fmt"
	"os"
	"strconv"
	"sync"
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

const numWorkers = 8

var messagesPerWorker = getMessages() / numWorkers

func worker(id int, inbox chan int, wg *sync.WaitGroup, result *int, sum *int64) {
	defer wg.Done()
	count := 0
	var s int64 // the values this worker received
	for v := range inbox {
		s += int64(v)
		count++
	}
	*result = count
	*sum = s
}

func main() {
	total := numWorkers * messagesPerWorker
	fmt.Println("=== Go Fork-Join Throughput Benchmark ===")
	fmt.Printf("Workers: %d, Messages: %d\n\n", numWorkers, total)

	// Create worker channels
	channels := make([]chan int, numWorkers)
	results := make([]int, numWorkers)
	sums := make([]int64, numWorkers)
	var wg sync.WaitGroup

	for i := 0; i < numWorkers; i++ {
		channels[i] = make(chan int, 1024)
		wg.Add(1)
		go worker(i, channels[i], &wg, &results[i], &sums[i])
	}

	start := time.Now()

	// Send messages round-robin
	for i := 0; i < total; i++ {
		channels[i%numWorkers] <- i
	}

	// Close all channels
	for i := 0; i < numWorkers; i++ {
		close(channels[i])
	}

	// Wait for all workers
	wg.Wait()

	elapsed := time.Since(start)

	// Collect results
	totalProcessed := 0
	var checksum int64
	for i := 0; i < numWorkers; i++ {
		totalProcessed += results[i]
		checksum += sums[i]
	}

	if totalProcessed != total {
		fmt.Printf("VALIDATION FAILED: expected %d, got %d\n", total, totalProcessed)
	}

	elapsedSec := elapsed.Seconds()
	throughput := float64(total) / elapsedSec / 1e6
	nsPerMsg := elapsedSec * 1e9 / float64(total)

	fmt.Printf("Checksum: %d\n", checksum)
	fmt.Printf("ns/msg:         %.2f\n", nsPerMsg)
	fmt.Printf("Throughput:     %.2f M msg/sec\n", throughput)
}
