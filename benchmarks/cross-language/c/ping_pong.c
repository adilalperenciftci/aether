// C ping-pong benchmark: two pthreads, each with a mailbox (mailbox.h).
// Ping sends 0, 1, 2, ...; pong echoes each value back; ping checks it.
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdint.h>
#include <time.h>

#include "mailbox.h"

// Configurable via BENCHMARK_MESSAGES env var, default 100K for "low" preset
static int MESSAGES = 100000;

static mailbox_t to_ping, to_pong;

/* The sum of the values ping got back, which the runner checks. */
static long long checksum = 0;

static void* ping_thread(void* arg) {
    (void)arg;
    long long sum = 0;
    for (int i = 0; i < MESSAGES; i++) {
        mailbox_send(&to_pong, i);
        int64_t received = mailbox_receive(&to_ping);
        sum += received;
        if (received != i) {
            fprintf(stderr, "ERROR: Ping sent %d but got back %lld\n", i, (long long)received);
        }
    }
    checksum = sum;
    return NULL;
}

static void* pong_thread(void* arg) {
    (void)arg;
    for (int i = 0; i < MESSAGES; i++) {
        int64_t received = mailbox_receive(&to_pong);
        if (received != i) {
            fprintf(stderr, "ERROR: Pong expected %d but got %lld\n", i, (long long)received);
        }
        mailbox_send(&to_ping, received);
    }
    return NULL;
}

static inline uint64_t get_time_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

int main(void) {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) MESSAGES = atoi(env);

    printf("=== C (pthread) Ping-Pong Benchmark ===\n");
    printf("Messages: %d\n", MESSAGES);
    printf("Using pthreads with C11-atomic mailboxes (spin, then sleep)\n\n");

    uint64_t start = get_time_ns();

    // One message in flight each way, so a mailbox of one slot.
    mailbox_init(&to_ping, 1);
    mailbox_init(&to_pong, 1);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, ping_thread, NULL);
    pthread_create(&t2, NULL, pong_thread, NULL);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);

    uint64_t end = get_time_ns();
    uint64_t elapsed_ns = end - start;
    if (elapsed_ns < 1) elapsed_ns = 1;
    double elapsed_sec = (double)elapsed_ns / 1e9;
    double throughput = MESSAGES / elapsed_sec;
    double ns_per_msg = (double)elapsed_ns / MESSAGES;

    printf("Checksum: %lld\n", checksum);
    printf("ns/msg:         %.2f\n", ns_per_msg);
    printf("Throughput:     %.2f M msg/sec\n", throughput / 1e6);

    mailbox_destroy(&to_ping);
    mailbox_destroy(&to_pong);
    return 0;
}
