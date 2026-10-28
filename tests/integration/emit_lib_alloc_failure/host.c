/* A C host of alloc.ae (#2956). Each call's allocation fails and the call
 * must come back with the zero value and the outcome, its defers run, and
 * the library takes the next call:
 *
 *   cap 0 outcome 4 "..." defers 1     past a memory cap
 *   guarded 0 outcome 4 defers 2       the same inside a user try
 *   oom 0 outcome 5 "..." defers 3     the allocator out of memory
 *   after 160 outcome 0 defers 4       a fresh call, no cap
 *
 * The library's C is linked into this program (one runtime). */
#include <stdio.h>
#include <stdint.h>
#include "libaether.h"

extern int aether_build(int);
extern int aether_guarded_build(int);
/* Runtime-internal: the bytes the cap counts now, and the test hook that
 * fails the n-th cap-aware allocation from now on this thread. */
extern uint64_t aether_caps_used_bytes(void);
extern void aether_test_fail_alloc_after(int n);

static int defers;
void host_defer_ran(void) { defers++; }

int main(void) {
    aether_set_memory_cap(aether_caps_used_bytes() + 65536);
    int r = aether_build(1000000);
    printf("cap %d outcome %d \"%s\" defers %d\n", r, aether_last_outcome(), aether_last_outcome_text(),
           defers);
    r = aether_guarded_build(1000000);
    printf("guarded %d outcome %d defers %d\n", r, aether_last_outcome(), defers);
    aether_set_memory_cap(0);

    aether_test_fail_alloc_after(3);
    r = aether_build(100);
    printf("oom %d outcome %d \"%s\" defers %d\n", r, aether_last_outcome(), aether_last_outcome_text(),
           defers);

    r = aether_build(10);
    printf("after %d outcome %d defers %d\n", r, aether_last_outcome(), defers);
    fflush(stdout);
    return 0;
}
