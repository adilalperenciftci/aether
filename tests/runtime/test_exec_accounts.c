/**
 * Execution accounts (#2954) after the review of their fixes: what a free,
 * a nesting and a parent do to them.
 *
 * - #3407: freeing an account leaves nothing naming it: not the thread's
 *   account in use, not an execution that began under it.
 * - #3408: freeing an account credits its ancestors with what its live
 *   blocks were charged, and its children keep narrowing under its parent.
 * - #3409: an ACTIVE account is charged once for time spent in executions
 *   under it, however they nest, and however many are timed at once.
 * - #3410: freeing an account is linear in its blocks.
 */

#include "test_harness.h"
#include "../../runtime/aether_exec.h"
#include "../../runtime/aether_resource_caps.h"
#include "../../runtime/actors/aether_panic.h"
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#define ea_sleep_ms(ms) Sleep(ms)
static double ea_now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}
#else
#include <unistd.h>
#include <time.h>
#define ea_sleep_ms(ms) usleep((ms) * 1000)
static double ea_now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}
#endif

static AetherExecAccount* ea_new(uint64_t bytes, int64_t ms, int counts, AetherExecAccount* parent) {
    AetherExecLimits l = { bytes, ms, counts, parent };
    return aether_exec_account_new(&l);
}

/* #3407: an account put in use, then freed, is in use no more. */
TEST_CATEGORY(accounts_free_ends_its_use, TEST_CATEGORY_RUNTIME) {
    AetherExecAccount* a = ea_new(1 << 20, 0, AETHER_DEADLINE_ELAPSED, NULL);
    ASSERT_NOT_NULL(a);
    ASSERT_EQ(0, aether_exec_use(a, NULL));
    aether_exec_account_free(a);
    AetherExecAccount* here = aether_account_here();
    void* p = aether_caps_malloc(80);
    aether_caps_free(p, 80);
    aether_exec_use(NULL, NULL);
    ASSERT_NULL(here);
}

/* #3407: an execution that began under an account the code it runs frees
 * gives nothing back to it: after it, no account is in use. */
static AetherExecAccount* g_ea_freed;

static void ea_run_freeing(int switch_first) {
    AetherJmpFrame* x = aether_exec_enter();
    if (AETHER_SIGSETJMP(x->buf, 1)) {
        aether_exec_failed();
        return;
    }
    if (switch_first) aether_exec_use(NULL, NULL);
    aether_exec_account_free(g_ea_freed);
    void* p = aether_caps_malloc(64);
    aether_caps_free(p, 64);
    aether_exec_leave();
}

TEST_CATEGORY(accounts_free_inside_an_execution_under_it, TEST_CATEGORY_RUNTIME) {
    AetherExecAccount* in_use_after[2];
    int outcome[2];
    for (int k = 0; k < 2; k++) {
        g_ea_freed = ea_new(1 << 20, 0, AETHER_DEADLINE_ELAPSED, NULL);
        ASSERT_NOT_NULL(g_ea_freed);
        ASSERT_EQ(0, aether_exec_use(g_ea_freed, NULL));
        ea_run_freeing(k);
        outcome[k] = aether_last_outcome();
        in_use_after[k] = aether_account_here();
        aether_exec_use(NULL, NULL);
    }
    ASSERT_EQ(AETHER_OK, outcome[0]);
    ASSERT_EQ(AETHER_OK, outcome[1]);
    ASSERT_NULL(in_use_after[0]);   // freed while in use
    ASSERT_NULL(in_use_after[1]);   // freed after the code put it out of use
}

/* #3408: a child freed while its blocks live credits its parent with them;
 * a parent freed under its children leaves them under its own parent. */
TEST_CATEGORY(accounts_free_credits_the_ancestors, TEST_CATEGORY_RUNTIME) {
    AetherExecAccount* p = ea_new(0, 0, AETHER_DEADLINE_ELAPSED, NULL);
    AetherExecAccount* c = ea_new(0, 0, AETHER_DEADLINE_ELAPSED, p);
    ASSERT_NOT_NULL(c);
    aether_exec_use(c, NULL);
    void* b = aether_caps_malloc(1000);
    aether_exec_use(NULL, NULL);
    uint64_t parent_before = aether_exec_account_used(p);
    aether_exec_account_free(c);
    uint64_t parent_after_free = aether_exec_account_used(p);
    aether_caps_free(b, 1000);
    uint64_t parent_after_block = aether_exec_account_used(p);

    AetherExecAccount* g = ea_new(0, 0, AETHER_DEADLINE_ELAPSED, NULL);
    AetherExecAccount* m = ea_new(0, 0, AETHER_DEADLINE_ELAPSED, g);
    AetherExecAccount* k = ea_new(0, 0, AETHER_DEADLINE_ELAPSED, m);
    aether_exec_use(k, NULL);
    void* q = aether_caps_malloc(500);
    aether_exec_use(NULL, NULL);
    aether_exec_account_free(m);
    uint64_t grand_after_free = aether_exec_account_used(g);
    aether_caps_free(q, 500);
    uint64_t grand_after_block = aether_exec_account_used(g);
    uint64_t child_after_block = aether_exec_account_used(k);
    aether_exec_account_free(k);
    aether_exec_account_free(g);
    aether_exec_account_free(p);

    ASSERT_EQ(1000, parent_before);
    ASSERT_EQ(0, parent_after_free);
    ASSERT_EQ(0, parent_after_block);
    ASSERT_EQ(500, grand_after_free);
    ASSERT_EQ(0, grand_after_block);
    ASSERT_EQ(0, child_after_block);
}

/* #3409: 200 ms spent in an execution nested inside another, both under one
 * ACTIVE account of 300 ms (and under a child of it), is 200 ms of it: the
 * next execution under it is not cut, and one of 150 ms more is. */
static int ea_nested(AetherExecAccount* inner) {
    AetherJmpFrame* x = aether_exec_enter();
    if (AETHER_SIGSETJMP(x->buf, 1)) {
        aether_exec_failed();
        return aether_last_outcome();
    }
    AetherExecAccount* outer = NULL;
    if (inner) aether_exec_use(inner, &outer);
    AetherJmpFrame* y = aether_exec_enter();
    if (AETHER_SIGSETJMP(y->buf, 1)) {
        aether_exec_failed();
    } else {
        ea_sleep_ms(200);
        aether_exec_leave();
    }
    if (inner) aether_exec_use(outer, NULL);
    aether_exec_leave();
    return aether_last_outcome();
}

static int ea_poll_under(int ms) {
    AetherJmpFrame* x = aether_exec_enter();
    if (AETHER_SIGSETJMP(x->buf, 1)) {
        aether_exec_failed();
        return aether_last_outcome();
    }
    ea_sleep_ms(ms);
    (void)aether_exec_poll();
    aether_exec_leave();
    return aether_last_outcome();
}

TEST_CATEGORY(accounts_active_time_once_when_nested, TEST_CATEGORY_RUNTIME) {
    int first[2], next[2], tripped[2], past[2];
    for (int k = 0; k < 2; k++) {
        AetherExecAccount* a = ea_new(0, 300, AETHER_DEADLINE_ACTIVE, NULL);
        AetherExecAccount* child = k ? ea_new(0, 0, AETHER_DEADLINE_ELAPSED, a) : NULL;
        aether_exec_use(a, NULL);
        first[k] = ea_nested(child);
        next[k] = ea_poll_under(10);
        tripped[k] = aether_exec_account_tripped(a);
        past[k] = ea_poll_under(150);   /* 200 + 10 + 150: past its 300 */
        aether_exec_use(NULL, NULL);
        if (child) aether_exec_account_free(child);
        aether_exec_account_free(a);
    }
    ASSERT_EQ(AETHER_OK, first[0]);
    ASSERT_EQ(AETHER_OK, next[0]);
    ASSERT_EQ(0, tripped[0]);
    ASSERT_EQ(AETHER_OK, first[1]);
    ASSERT_EQ(AETHER_OK, next[1]);
    ASSERT_EQ(0, tripped[1]);
    ASSERT_EQ(AETHER_DEADLINE, past[0]);
    ASSERT_EQ(AETHER_DEADLINE, past[1]);
}


/* #3409: more ACTIVE accounts timed at once on one thread than its list
 * holds inline (and than the 16 it once held), each in use in an execution
 * nested inside the one before: every one is charged its time. */
#define EA_DEEP 20
static AetherExecAccount* g_ea_deep[EA_DEEP];

static void ea_deep(int i) {
    AetherJmpFrame* x = aether_exec_enter();
    if (AETHER_SIGSETJMP(x->buf, 1)) {
        aether_exec_failed();
        return;
    }
    if (i + 1 < EA_DEEP) {
        AetherExecAccount* prev = NULL;
        aether_exec_use(g_ea_deep[i + 1], &prev);
        ea_deep(i + 1);
        aether_exec_use(prev, NULL);
    } else {
        ea_sleep_ms(50);
    }
    aether_exec_leave();
}

TEST_CATEGORY(accounts_active_time_many_nested, TEST_CATEGORY_RUNTIME) {
    for (int i = 0; i < EA_DEEP; i++) g_ea_deep[i] = ea_new(0, 10000, AETHER_DEADLINE_ACTIVE, NULL);
    aether_exec_use(g_ea_deep[0], NULL);
    ea_deep(0);
    int outcome = aether_last_outcome();
    aether_exec_use(NULL, NULL);
    int charged = 0;
    for (int i = 0; i < EA_DEEP; i++) {
        if (atomic_load(&g_ea_deep[i]->active_spent_ns) >= 45 * 1000000LL) charged++;
        aether_exec_account_free(g_ea_deep[i]);
    }
    ASSERT_EQ(AETHER_OK, outcome);
    ASSERT_EQ(EA_DEEP, charged);
}
/* #3410: freeing an account of 4n blocks takes about four times as long as
 * one of n, not sixteen. The best of three runs of each, with another
 * account live, so the table outlives the free. */
static double ea_free_ms(int n) {
    double best = 1e18;
    AetherExecAccount* keep = ea_new(0, 0, AETHER_DEADLINE_ELAPSED, NULL);
    void** blocks = (void**)malloc(sizeof(void*) * (size_t)n);
    for (int run = 0; run < 3; run++) {
        AetherExecAccount* a = ea_new(0, 0, AETHER_DEADLINE_ELAPSED, NULL);
        aether_exec_use(a, NULL);
        for (int i = 0; i < n; i++) blocks[i] = aether_caps_malloc(32);
        aether_exec_use(NULL, NULL);
        double t0 = ea_now_ms();
        aether_exec_account_free(a);
        double t = ea_now_ms() - t0;
        if (t < best) best = t;
        for (int i = 0; i < n; i++) aether_caps_free(blocks[i], 32);
    }
    aether_exec_account_free(keep);
    free(blocks);
    return best;
}

TEST_CATEGORY(accounts_free_is_linear_in_its_blocks, TEST_CATEGORY_RUNTIME) {
    double small = ea_free_ms(10000);
    double large = ea_free_ms(40000);
    if (small < 0.05) small = 0.05;   /* below the timer's grain both are fast */
    fprintf(stderr, "    account_free: 10000 blocks %.2f ms, 40000 blocks %.2f ms\n", small, large);
    ASSERT_TRUE(large < small * 8.0 || large < 2.0);
}

