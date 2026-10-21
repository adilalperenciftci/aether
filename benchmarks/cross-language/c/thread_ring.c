// C Thread Ring Benchmark (Savina-style)
// 100 threads in a ring, each with a mailbox (mailbox.h), pass a token that
// counts down from the hop count; the node that receives 0 tells main.

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>

/* No spinning: a node waits about 99 hops for the token, and 100 spinning
 * threads on fewer cores take the CPU from the one thread that holds it
 * (FAIRNESS.md, wait strategies). */
#define MAILBOX_SPIN 0
#include "mailbox.h"

#define RING_SIZE 100
static int NUM_HOPS = 100000;  // Default for "low" preset

static mailbox_t inbox[RING_SIZE];
static mailbox_t done_box;          /* main's: the node that gets 0 writes here */
static long long received[RING_SIZE];

static void* node_thread(void* arg) {
    int id = (int)(intptr_t)arg;
    mailbox_t* next = &inbox[(id + 1) % RING_SIZE];
    for (;;) {
        int64_t token = mailbox_receive(&inbox[id]);
        if (token < 0) break;            /* main's stop, after the run */
        received[id]++;
        if (token == 0) {
            mailbox_send(&done_box, 0);
        } else {
            mailbox_send(next, token - 1);
        }
    }
    return NULL;
}

int main(void) {
    const char* env = getenv("BENCHMARK_MESSAGES");
    if (env) NUM_HOPS = atoi(env);

    printf("=== C Thread Ring Benchmark ===\n");
    printf("Ring size: %d, Hops: %d\n\n", RING_SIZE, NUM_HOPS);

    pthread_t threads[RING_SIZE];

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    // One token in the ring, so a mailbox of one slot.
    mailbox_init(&done_box, 1);
    for (int i = 0; i < RING_SIZE; i++) mailbox_init(&inbox[i], 1);
    for (int i = 0; i < RING_SIZE; i++) {
        pthread_create(&threads[i], NULL, node_thread, (void*)(intptr_t)i);
    }

    mailbox_send(&inbox[0], NUM_HOPS);
    mailbox_receive(&done_box);

    clock_gettime(CLOCK_MONOTONIC, &end);

    // The token is spent and nothing sends any more: stop every node.
    for (int i = 0; i < RING_SIZE; i++) mailbox_send(&inbox[i], -1);
    for (int i = 0; i < RING_SIZE; i++) pthread_join(threads[i], NULL);

    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    if (elapsed <= 0) elapsed = 1e-9;
    int total_messages = NUM_HOPS + 1;
    double throughput = total_messages / elapsed / 1e6;
    double ns_per_msg = elapsed * 1e9 / total_messages;

    /* The receipts summed over the ring, the checksum. */
    long long receipts = 0;
    for (int i = 0; i < RING_SIZE; i++) receipts += received[i];
    printf("Checksum: %lld\n", receipts);
    printf("ns/msg:         %.2f\n", ns_per_msg);
    printf("Throughput:     %.2f M msg/sec\n", throughput);

    for (int i = 0; i < RING_SIZE; i++) mailbox_destroy(&inbox[i]);
    mailbox_destroy(&done_box);
    return 0;
}
