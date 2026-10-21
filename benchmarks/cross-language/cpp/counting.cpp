// C++ Counting Actor Benchmark (Savina-style)
// One counter thread receives N messages through its mailbox (mailbox.hpp)
// and counts them; a final -1 tells it to stop.
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <thread>

#include "mailbox.hpp"

static int MESSAGES = 100000;  // Default for "low" preset

// 1024 messages, the mailbox size of every language here that bounds one
// (FAIRNESS.md, techniques).
constexpr std::uint32_t CAPACITY = 1024;

int main() {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) MESSAGES = atoi(env);

    std::cout << "=== C++ Counting Actor Benchmark ===" << std::endl;
    std::cout << "Messages: " << MESSAGES << "\n" << std::endl;

    long long processed = 0;   // the messages the counter took, the checksum

    auto start = std::chrono::steady_clock::now();

    Mailbox inbox(CAPACITY);
    std::thread counter([&] {
        long long count = 0;
        while (inbox.receive() >= 0) count++;
        processed = count;
    });

    for (int i = 0; i < MESSAGES; i++) {
        inbox.send(i);
    }
    inbox.send(-1);

    counter.join();

    auto end = std::chrono::steady_clock::now();
    double elapsed = std::chrono::duration<double>(end - start).count();
    if (elapsed <= 0) elapsed = 1e-9;

    if (processed != MESSAGES) {
        std::cout << "VALIDATION FAILED: expected " << MESSAGES
                  << ", got " << processed << std::endl;
    }

    double throughput = MESSAGES / elapsed / 1e6;
    double ns_per_msg = elapsed * 1e9 / MESSAGES;

    std::cout << "Checksum: " << processed << std::endl;
    std::cout << "ns/msg:         " << std::fixed << std::setprecision(2) << ns_per_msg << std::endl;
    std::cout << "Throughput:     " << std::setprecision(2) << throughput << " M msg/sec" << std::endl;

    return 0;
}
