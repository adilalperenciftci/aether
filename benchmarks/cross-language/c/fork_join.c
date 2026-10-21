// C Fork-Join Benchmark (Savina-style)
// 8 worker threads, each with a mailbox (mailbox.h); main sends the
// messages round-robin, then a -1 to each, and joins them.

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>

#include "mailbox.h"

#define NUM_WORKERS 8
static int MESSAGES_PER_WORKER = 12500;  // Default for "low" preset (100000 / 8)

// 1024 messages, the mailbox size of every language here that bounds one
// (FAIRNESS.md, techniques).
#define CAPACITY 1024

typedef struct {
    mailbox_t inbox;
    long long processed;
    long long sum;   /* the values this worker received */
} Worker;

static Worker workers[NUM_WORKERS];

static void* worker_thread(void* arg) {
    Worker* self = (Worker*)arg;
    long long processed = 0, sum = 0;
    for (;;) {
        int64_t value = mailbox_receive(&self->inbox);
        if (value < 0) break;
        sum += value;
        processed++;
    }
    self->processed = processed;
    self->sum = sum;
    return NULL;
}

int main(void) {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) MESSAGES_PER_WORKER = atoi(env) / NUM_WORKERS;

    int total = NUM_WORKERS * MESSAGES_PER_WORKER;
    printf("=== C Fork-Join Throughput Benchmark ===\n");
    printf("Workers: %d, Messages: %d\n\n", NUM_WORKERS, total);

    pthread_t threads[NUM_WORKERS];

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int i = 0; i < NUM_WORKERS; i++) {
        mailbox_init(&workers[i].inbox, CAPACITY);
        pthread_create(&threads[i], NULL, worker_thread, &workers[i]);
    }

    // Send messages round-robin
    for (int i = 0; i < total; i++) {
        mailbox_send(&workers[i % NUM_WORKERS].inbox, i);
    }
    for (int i = 0; i < NUM_WORKERS; i++) {
        mailbox_send(&workers[i].inbox, -1);
    }
    for (int i = 0; i < NUM_WORKERS; i++) {
        pthread_join(threads[i], NULL);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);

    long long total_processed = 0;
    long long checksum = 0;
    for (int i = 0; i < NUM_WORKERS; i++) {
        total_processed += workers[i].processed;
        checksum += workers[i].sum;
    }

    if (total_processed != total) {
        printf("VALIDATION FAILED: expected %d, got %lld\n", total, total_processed);
    }

    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    if (elapsed <= 0) elapsed = 1e-9;
    double throughput = total / elapsed / 1e6;
    double ns_per_msg = elapsed * 1e9 / total;

    printf("Checksum: %lld\n", checksum);
    printf("ns/msg:         %.2f\n", ns_per_msg);
    printf("Throughput:     %.2f M msg/sec\n", throughput);

    for (int i = 0; i < NUM_WORKERS; i++) mailbox_destroy(&workers[i].inbox);
    return 0;
}
