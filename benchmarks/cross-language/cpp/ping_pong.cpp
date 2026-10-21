// C++ Ping-Pong Benchmark: two std::threads, each with a mailbox
// (mailbox.hpp). Ping sends 0, 1, 2, ...; pong echoes each value back;
// ping checks it.

#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <thread>

#include "mailbox.hpp"

static int MESSAGES = 100000;  // Default for "low" preset

int main() {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) MESSAGES = atoi(env);

    std::cout << "=== C++ Ping-Pong Benchmark ===" << std::endl;
    std::cout << "Messages: " << MESSAGES << std::endl;
    std::cout << "Using std::thread with std::atomic mailboxes (spin, then sleep)\n" << std::endl;

    // The sum of the values ping got back, which the runner checks.
    long long checksum = 0;

    auto start = std::chrono::steady_clock::now();

    // One message in flight each way, so a mailbox of one slot.
    Mailbox to_ping(1), to_pong(1);

    std::thread ping([&] {
        long long sum = 0;
        for (int i = 0; i < MESSAGES; i++) {
            to_pong.send(i);
            std::int64_t received = to_ping.receive();
            sum += received;
            if (received != i) {
                std::cerr << "ERROR: Ping sent " << i << " but got back " << received << std::endl;
            }
        }
        checksum = sum;
    });
    std::thread pong([&] {
        for (int i = 0; i < MESSAGES; i++) {
            std::int64_t received = to_pong.receive();
            if (received != i) {
                std::cerr << "ERROR: Pong expected " << i << " but got " << received << std::endl;
            }
            to_ping.send(received);
        }
    });

    ping.join();
    pong.join();

    auto end = std::chrono::steady_clock::now();
    double elapsed = std::chrono::duration<double>(end - start).count();
    if (elapsed <= 0) elapsed = 1e-9;
    double throughput = MESSAGES / elapsed / 1e6;
    double ns_per_msg = elapsed * 1e9 / MESSAGES;

    std::cout << "Checksum: " << checksum << std::endl;
    std::cout << "ns/msg:         " << std::fixed << std::setprecision(2) << ns_per_msg << std::endl;
    std::cout << "Throughput:     " << std::fixed << std::setprecision(2) << throughput << " M msg/sec" << std::endl;

    return 0;
}
