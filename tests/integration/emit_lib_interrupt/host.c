/* A C host of work.ae (#2956, D5). Each call is ended from outside its code
 * and must come back with the zero value and the outcome, its defers run,
 * and the library takes the next call:
 *
 *   spin 0 outcome 2 defers 1            a loop cut by a 5 ms deadline
 *   guarded 0 outcome 2 defers 2         the same inside a user try
 *   parse outcome 2                      a large JSON parse, 5 ms deadline
 *   parse 3 outcome 0                    a small one, no deadline
 *   cancel 0 outcome 3 defers 3          cancelled from another thread
 *   after -5 outcome 0 defers 4          a fresh call
 *
 * With the argument cancel-first, a fresh process cancels a call before
 * anything armed a deadline (the loop heads' flag was 0 when the loop
 * began):
 *
 *   cancel 0 outcome 3 defers 1
 *
 * The library's C is linked into this program (one runtime). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <pthread.h>
#include "libaether.h"

extern int aether_spin(int);
extern int aether_guarded(int);
extern int aether_parse_size(const char*);

static int defers;
void host_defer_ran(void) { defers++; }

/* The cancel: the worker takes the token of the call it is about to make,
 * says so, and makes it; this thread cancels once it has heard. */
static atomic_int g_ready;
static AetherExecToken g_token;
static int g_cancel_ret, g_cancel_outcome;

static void* worker(void* arg) {
    (void)arg;
    aether_set_call_deadline(0);
    g_token = aether_exec_token();
    atomic_store(&g_ready, 1);
    g_cancel_ret = aether_spin(2000000000);
    g_cancel_outcome = aether_last_outcome();
    return NULL;
}

/* A call on another thread, cancelled from this one. */
static void run_cancel(void) {
    pthread_t t;
    atomic_store(&g_ready, 0);
    if (pthread_create(&t, NULL, worker, NULL) != 0) { printf("no thread\n"); return; }
    while (!atomic_load(&g_ready)) { }
    if (aether_exec_cancel(g_token) != 0) printf("cancel refused\n");
    pthread_join(t, NULL);
    printf("cancel %d outcome %d defers %d\n", g_cancel_ret, g_cancel_outcome, defers);
}

int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "cancel-first") == 0) {
        run_cancel();
        fflush(stdout);
        return 0;
    }
    aether_set_call_deadline(5);
    int r = aether_spin(2000000000);
    printf("spin %d outcome %d defers %d\n", r, aether_last_outcome(), defers);

    aether_set_call_deadline(5);
    r = aether_guarded(2000000000);
    printf("guarded %d outcome %d defers %d\n", r, aether_last_outcome(), defers);

    /* [0,0,...]: a few million elements, far more than 5 ms of parsing. */
    size_t n = 4000000;
    char* doc = (char*)malloc(n * 2 + 2);
    if (!doc) return 1;
    doc[0] = '[';
    for (size_t i = 0; i < n; i++) { doc[1 + 2 * i] = '0'; doc[2 + 2 * i] = ','; }
    doc[2 * n] = ']';
    doc[2 * n + 1] = '\0';
    aether_set_call_deadline(5);
    (void)aether_parse_size(doc);
    printf("parse outcome %d\n", aether_last_outcome());
    free(doc);

    aether_set_call_deadline(0);
    r = aether_parse_size("[1,2,3]");
    printf("parse %d outcome %d\n", r, aether_last_outcome());

    run_cancel();

    r = aether_spin(10);
    printf("after %d outcome %d defers %d\n", r, aether_last_outcome(), defers);
    fflush(stdout);
    return 0;
}
