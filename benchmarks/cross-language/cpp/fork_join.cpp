// C++ Fork-Join Benchmark (Savina-style)
// 8 worker std::threads, each with a mailbox (mailbox.hpp); main sends the
// messages round-robin, then a -1 to each, and joins them.
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <memory>
#include <thread>
#include <vector>

#include "mailbox.hpp"

constexpr int NUM_WORKERS = 8;
static int MESSAGES_PER_WORKER = 12500;  // Default for "low" preset (100000 / 8)

// 1024 messages, the mailbox size of every language here that bounds one
// (FAIRNESS.md, techniques).
constexpr std::uint32_t CAPACITY = 1024;

struct Worker {
    Mailbox inbox{CAPACITY};
    long long processed = 0;
    long long sum = 0;   // the values this worker received

    void run() {
        long long n = 0, s = 0;
        for (;;) {
            std::int64_t value = inbox.receive();
            if (value < 0) break;
            s += value;
            n++;
        }
        processed = n;
        sum = s;
    }
};

int main() {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) MESSAGES_PER_WORKER = atoi(env) / NUM_WORKERS;

    int total = NUM_WORKERS * MESSAGES_PER_WORKER;
    std::cout << "=== C++ Fork-Join Throughput Benchmark ===" << std::endl;
    std::cout << "Workers: " << NUM_WORKERS << ", Messages: " << total << "\n" << std::endl;

    std::vector<std::unique_ptr<Worker>> workers;
    std::vector<std::thread> threads;

    auto start = std::chrono::steady_clock::now();

    for (int i = 0; i < NUM_WORKERS; i++) {
        workers.push_back(std::make_unique<Worker>());
        threads.emplace_back(&Worker::run, workers[i].get());
    }

    // Send messages round-robin
    for (int i = 0; i < total; i++) {
        workers[i % NUM_WORKERS]->inbox.send(i);
    }
    for (int i = 0; i < NUM_WORKERS; i++) {
        workers[i]->inbox.send(-1);
    }
    for (auto& t : threads) {
        t.join();
    }

    auto end = std::chrono::steady_clock::now();
    double elapsed = std::chrono::duration<double>(end - start).count();
    if (elapsed <= 0) elapsed = 1e-9;

    long long total_processed = 0;
    long long checksum = 0;
    for (int i = 0; i < NUM_WORKERS; i++) {
        total_processed += workers[i]->processed;
        checksum += workers[i]->sum;
    }

    if (total_processed != total) {
        std::cout << "VALIDATION FAILED: expected " << total
                  << ", got " << total_processed << std::endl;
    }

    double throughput = total / elapsed / 1e6;
    double ns_per_msg = elapsed * 1e9 / total;

    std::cout << "Checksum: " << checksum << std::endl;
    std::cout << "ns/msg:         " << std::fixed << std::setprecision(2) << ns_per_msg << std::endl;
    std::cout << "Throughput:     " << std::setprecision(2) << throughput << " M msg/sec" << std::endl;

    return 0;
}
