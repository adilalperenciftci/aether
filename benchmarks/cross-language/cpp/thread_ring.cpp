// C++ Thread Ring Benchmark (Savina-style)
// 100 std::threads in a ring, each with a mailbox (mailbox.hpp), pass a
// token that counts down from the hop count; the node that receives 0 tells
// main.
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <thread>
#include <vector>

// No spinning: a node waits about 99 hops for the token, and 100 spinning
// threads on fewer cores take the CPU from the one thread that holds it
// (FAIRNESS.md, wait strategies).
#define MAILBOX_SPIN 0
#include "mailbox.hpp"

constexpr int RING_SIZE = 100;
static int NUM_HOPS = 100000;  // Default for "low" preset

// One token in the ring, so a mailbox of one slot (the default).
static Mailbox inbox[RING_SIZE];
static Mailbox done_box;            // main's: the node that gets 0 writes here
static long long received[RING_SIZE];

static void node(int id) {
    Mailbox& next = inbox[(id + 1) % RING_SIZE];
    for (;;) {
        std::int64_t token = inbox[id].receive();
        if (token < 0) break;           // main's stop, after the run
        received[id]++;
        if (token == 0) {
            done_box.send(0);
        } else {
            next.send(token - 1);
        }
    }
}

int main() {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) NUM_HOPS = atoi(env);

    std::cout << "=== C++ Thread Ring Benchmark ===" << std::endl;
    std::cout << "Ring size: " << RING_SIZE << ", Hops: " << NUM_HOPS << "\n" << std::endl;

    std::vector<std::thread> threads;
    threads.reserve(RING_SIZE);

    auto start = std::chrono::steady_clock::now();

    for (int i = 0; i < RING_SIZE; i++) {
        threads.emplace_back(node, i);
    }

    inbox[0].send(NUM_HOPS);
    done_box.receive();

    auto end = std::chrono::steady_clock::now();

    // The token is spent and nothing sends any more: stop every node.
    for (int i = 0; i < RING_SIZE; i++) inbox[i].send(-1);
    for (auto& t : threads) t.join();

    double elapsed = std::chrono::duration<double>(end - start).count();
    if (elapsed <= 0) elapsed = 1e-9;
    int total_messages = NUM_HOPS + 1;

    double throughput = total_messages / elapsed / 1e6;
    double ns_per_msg = elapsed * 1e9 / total_messages;

    // The receipts summed over the ring, the checksum.
    long long receipts = 0;
    for (int i = 0; i < RING_SIZE; i++) receipts += received[i];
    std::cout << "Checksum: " << receipts << std::endl;
    std::cout << "ns/msg:         " << std::fixed << std::setprecision(2) << ns_per_msg << std::endl;
    std::cout << "Throughput:     " << std::setprecision(2) << throughput << " M msg/sec" << std::endl;

    return 0;
}
