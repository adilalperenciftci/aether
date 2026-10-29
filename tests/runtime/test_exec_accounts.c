/**
 * Execution accounts (#2954) after the review of their fixes: what a free,
 * a nesting and a parent do to them.
 *
 * - #3407: freeing an account leaves nothing naming it: not the thread's
 *   account in use, not an execution that began under it.
 * - #3408: freeing an account credits its ancestors with what its live
 *   blocks were charged, and its children keep narrowing under its parent.
 */

#include "test_harness.h"
#include "../../runtime/aether_exec.h"
#include "../../runtime/aether_resource_caps.h"
#include "../../runtime/actors/aether_panic.h"
#include <stdlib.h>
#include <string.h>

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

