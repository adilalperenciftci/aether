// C Counting Actor Benchmark (Savina-style)
// One counter thread receives N messages through its mailbox (mailbox.h)
// and counts them; a final -1 tells it to stop.

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>

#include "mailbox.h"

static int MESSAGES = 100000;  // Default for "low" preset

// 1024 messages, the mailbox size of every language here that bounds one
// (FAIRNESS.md, techniques).
#define CAPACITY 1024

static mailbox_t inbox;
static long long processed = 0;   /* the messages the counter took, the checksum */

static void* counter_thread(void* arg) {
    (void)arg;
    long long count = 0;
    while (mailbox_receive(&inbox) >= 0) {
        count++;
    }
    processed = count;
    return NULL;
}

int main(void) {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) MESSAGES = atoi(env);

    printf("=== C Counting Actor Benchmark ===\n");
    printf("Messages: %d\n\n", MESSAGES);

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    mailbox_init(&inbox, CAPACITY);
    pthread_t thread;
    pthread_create(&thread, NULL, counter_thread, NULL);

    for (int i = 0; i < MESSAGES; i++) {
        mailbox_send(&inbox, i);
    }
    mailbox_send(&inbox, -1);

    pthread_join(thread, NULL);

    clock_gettime(CLOCK_MONOTONIC, &end);

    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    if (elapsed <= 0) elapsed = 1e-9;
    double throughput = MESSAGES / elapsed / 1e6;
    double ns_per_msg = elapsed * 1e9 / MESSAGES;

    printf("Checksum: %lld\n", processed);
    printf("ns/msg:         %.2f\n", ns_per_msg);
    printf("Throughput:     %.2f M msg/sec\n", throughput);

    mailbox_destroy(&inbox);
    return 0;
}
