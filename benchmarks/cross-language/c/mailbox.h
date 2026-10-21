/*
 * A mailbox for one sending thread and one receiving thread, the C
 * benchmarks' message channel. The C standard library has no channel, so
 * this is what an expert writes from it: a bounded ring of int64 values on
 * C11 atomics, with a sequence number in each slot (Vyukov's bounded queue,
 * for one sender and one receiver). The sender waits on a slot until its
 * sequence says the slot is free, the receiver until it says the slot is
 * full, so neither side ever reads the other's index: a message moves the
 * cache line of its slot and nothing else.
 *
 * Waiting (FAIRNESS.md, techniques): a receiver that finds its slot empty
 * spins up to MAILBOX_SPIN pauses, looking again after 1, 2, 4, ... 64 of
 * them (each look pulls the line away from the sender), then sleeps on a
 * condition variable until a send wakes it. A program whose threads
 * outnumber the cores sets MAILBOX_SPIN to 0 and sleeps at once. A sender
 * that finds its slot full spins, then yields: the receiver is running then
 * (it sleeps only on an empty slot), so the wait ends when it takes the next
 * message.
 */
#ifndef BENCH_MAILBOX_H
#define BENCH_MAILBOX_H

#include <pthread.h>
#include <sched.h>
#include <stdalign.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef MAILBOX_SPIN
#define MAILBOX_SPIN 1000
#endif

#if defined(__x86_64__) || defined(__i386__)
#define mailbox_pause() __builtin_ia32_pause()
#elif defined(__aarch64__) || defined(__arm__)
#define mailbox_pause() __asm__ __volatile__("yield")
#else
#define mailbox_pause() ((void)0)
#endif

typedef struct {
    /* i: free for the sender's i-th message; i + 1: holds it. */
    _Atomic uint64_t seq;
    int64_t value;
} mailbox_slot_t;

typedef struct {
    alignas(64) uint64_t head;   /* the receiver's next message */
    alignas(64) uint64_t tail;   /* the sender's next message */
    /* Where a receiver sleeps. A send reads `sleeping` and touches the rest
     * only when it is set. */
    alignas(64) atomic_int sleeping;
    pthread_mutex_t lock;
    pthread_cond_t wake;
    uint64_t mask;
    mailbox_slot_t *slots;
} mailbox_t;

/* capacity: a power of two. */
static void mailbox_init(mailbox_t *m, uint64_t capacity) {
    m->head = 0;
    m->tail = 0;
    atomic_init(&m->sleeping, 0);
    pthread_mutex_init(&m->lock, NULL);
    pthread_cond_init(&m->wake, NULL);
    m->mask = capacity - 1;
    m->slots = malloc(capacity * sizeof(mailbox_slot_t));
    if (!m->slots) {
        fprintf(stderr, "mailbox: out of memory\n");
        exit(1);
    }
    for (uint64_t i = 0; i < capacity; i++) atomic_init(&m->slots[i].seq, i);
}

static void mailbox_destroy(mailbox_t *m) {
    pthread_mutex_destroy(&m->lock);
    pthread_cond_destroy(&m->wake);
    free(m->slots);
}

static inline void mailbox_send(mailbox_t *m, int64_t value) {
    uint64_t t = m->tail;
    mailbox_slot_t *s = &m->slots[t & m->mask];
    if (atomic_load_explicit(&s->seq, memory_order_acquire) != t) {
        int spun = 0;
        for (int step = 1; atomic_load_explicit(&s->seq, memory_order_acquire) != t;
             step = step < 64 ? step * 2 : 64) {
            if (spun < MAILBOX_SPIN) {
                for (int i = 0; i < step; i++) mailbox_pause();
                spun += step;
            } else {
                sched_yield();
            }
        }
    }
    s->value = value;
    /* Sequentially consistent, with the load of `sleeping` after it and the
     * receiver's store to `sleeping` and load of `seq` in mailbox_park: of
     * the two sides, at least one sees the other's store, so a receiver
     * never sleeps on a message nobody wakes it for. */
    atomic_store_explicit(&s->seq, t + 1, memory_order_seq_cst);
    m->tail = t + 1;
    if (atomic_load_explicit(&m->sleeping, memory_order_seq_cst)) {
        pthread_mutex_lock(&m->lock);
        pthread_cond_signal(&m->wake);
        pthread_mutex_unlock(&m->lock);
    }
}

/* The receiver found slot s empty and waits for its sequence to be `full`:
 * spin, then sleep. */
static __attribute__((noinline)) void mailbox_park(mailbox_t *m, mailbox_slot_t *s, uint64_t full) {
    int spun = 0;
    for (int step = 1; spun < MAILBOX_SPIN; step = step < 64 ? step * 2 : 64) {
        for (int i = 0; i < step; i++) mailbox_pause();
        spun += step;
        if (atomic_load_explicit(&s->seq, memory_order_acquire) == full) return;
    }
    pthread_mutex_lock(&m->lock);
    atomic_store_explicit(&m->sleeping, 1, memory_order_seq_cst);
    while (atomic_load_explicit(&s->seq, memory_order_seq_cst) != full) {
        pthread_cond_wait(&m->wake, &m->lock);
    }
    atomic_store_explicit(&m->sleeping, 0, memory_order_relaxed);
    pthread_mutex_unlock(&m->lock);
}

static inline int64_t mailbox_receive(mailbox_t *m) {
    uint64_t h = m->head;
    mailbox_slot_t *s = &m->slots[h & m->mask];
    if (atomic_load_explicit(&s->seq, memory_order_acquire) != h + 1) mailbox_park(m, s, h + 1);
    int64_t value = s->value;
    /* Free for the sender's message one lap on. */
    atomic_store_explicit(&s->seq, h + m->mask + 1, memory_order_release);
    m->head = h + 1;
    return value;
}

#endif
