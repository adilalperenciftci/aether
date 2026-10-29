/* A C host of accts.ae (#2954): execution accounts. Each line is one of the
 * issue's acceptance items or the design's tests:
 *
 *   isolated:  A past its allowance, B and the host still usable
 *   kept:      what A handed over stays charged while B runs; resuming A
 *              does not reset its ceiling
 *   credit:    A's blocks freed under B, and by the host, credit A
 *   narrow:    a child of A cannot spend more than A has left; freed, both
 *              are back to zero
 *   std:       a list and a JSON document charged and refused like strings
 *   inject:    a deterministic allocation failure under an account
 *   deadline:  A's deadline ends A's call only; B's next call runs
 *   active:    an ACTIVE deadline does not count time suspended; an
 *              ELAPSED one does
 *   nested:    an export's frame puts its account back after a host
 *              service ran another export under another account
 *   thread:    an account in use on one thread is refused on another
 *   baseline:  the process count is back where it started
 *
 * HOST_STATIC: the library's generated C is linked into this program (one
 * runtime). Otherwise argv[1] is the library, loaded at run time, and the
 * host API is the library's own runtime's, or the shared runtime's argv[2]. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#ifdef _WIN32
#include <windows.h>
#define sleep_ms(ms) Sleep(ms)
#else
#include <time.h>
static void sleep_ms(int ms) { struct timespec t = { ms / 1000, (ms % 1000) * 1000000L }; nanosleep(&t, NULL); }
#endif

#ifndef AETHER_EXEC_ACCOUNT_DEFINED
#define AETHER_EXEC_ACCOUNT_DEFINED
typedef struct AetherExecAccount AetherExecAccount;
typedef struct {
    uint64_t memory_bytes;
    int64_t  deadline_ms;
    int      deadline_counts;
    AetherExecAccount* parent;
} AetherExecLimits;
#define AETHER_DEADLINE_ELAPSED 0
#define AETHER_DEADLINE_ACTIVE  1
#endif

typedef int (*int_fn)(int);
typedef const void* (*str_fn)(int);
typedef void* (*ptr_fn)(int);
typedef int (*drop_fn)(void*);
typedef int (*doc_fn)(const char*);
typedef void (*release_fn)(const void*);
typedef void (*service_fn)(int);
typedef void (*hooks_set_fn)(service_fn);
typedef AetherExecAccount* (*new_fn)(const AetherExecLimits*);
typedef void (*free_fn)(AetherExecAccount*);
typedef int (*use_fn)(AetherExecAccount*, AetherExecAccount**);
typedef uint64_t (*used_fn)(const AetherExecAccount*);
typedef int (*tripped_fn)(const AetherExecAccount*);
typedef int (*outcome_fn)(void);
typedef uint64_t (*caps_used_fn)(void);
typedef void (*fail_after_fn)(int);

static str_fn hand_over;
static int_fn grow, spin, outer, inner, count_list;
static ptr_fn keep_list;
static drop_fn drop_list;
static doc_fn parse_size;
static release_fn str_release;
static hooks_set_fn hooks;
static new_fn acct_new;
static free_fn acct_free;
static use_fn acct_use;
static used_fn acct_used;
static tripped_fn acct_tripped;
static outcome_fn outcome;
static caps_used_fn caps_used;
static fail_after_fn fail_after;

#ifdef HOST_STATIC
#include "libaether.h"
extern const void* aether_hand_over(int);
extern int aether_grow(int), aether_spin(int), aether_outer(int), aether_inner(int), aether_count_list(int);
extern void* aether_keep_list(int);
extern int aether_drop_list(void*);
extern int aether_parse_size(const char*);
extern void aether_accts_string_release(const void*);
extern void hooks_set(service_fn);
extern uint64_t aether_caps_used_bytes(void);
extern void aether_test_fail_alloc_after(int);

static int load(int argc, char** argv) {
    (void)argc; (void)argv;
    hand_over = aether_hand_over; grow = aether_grow; spin = aether_spin;
    outer = aether_outer; inner = aether_inner; keep_list = (ptr_fn)aether_keep_list;
    count_list = aether_count_list;
    drop_list = (drop_fn)aether_drop_list; parse_size = aether_parse_size;
    str_release = aether_accts_string_release; hooks = hooks_set;
    acct_new = aether_exec_account_new; acct_free = aether_exec_account_free;
    acct_use = aether_exec_use; acct_used = aether_exec_account_used;
    acct_tripped = aether_exec_account_tripped; outcome = aether_last_outcome;
    caps_used = aether_caps_used_bytes; fail_after = aether_test_fail_alloc_after;
    return 0;
}
#else
#ifdef _WIN32
typedef HMODULE lib_t;
static lib_t lib_open(const char* path) { return LoadLibraryA(path); }
static void* lib_sym(lib_t h, const char* name) {
    FARPROC p = GetProcAddress(h, name);
    void* v;
    memcpy(&v, &p, sizeof(v));
    return v;
}
#else
#include <dlfcn.h>
typedef void* lib_t;
static lib_t lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_GLOBAL); }
static void* lib_sym(lib_t h, const char* name) { return dlsym(h, name); }
#endif
#define BIND(var, from, name) do { void* p_ = lib_sym(from, name); \
    if (!p_) { printf("missing %s\n", name); return 1; } memcpy(&var, &p_, sizeof(p_)); } while (0)

static int load(int argc, char** argv) {
    if (argc < 2) { printf("usage: host <library> [<shared runtime>]\n"); return 1; }
    lib_t lib = lib_open(argv[1]);
    if (!lib) { printf("cannot load %s\n", argv[1]); return 1; }
    lib_t rt = argc > 2 ? lib_open(argv[2]) : lib;
    if (!rt) { printf("cannot load %s\n", argv[2]); return 1; }
    BIND(hand_over, lib, "aether_hand_over"); BIND(grow, lib, "aether_grow");
    BIND(spin, lib, "aether_spin"); BIND(outer, lib, "aether_outer");
    BIND(inner, lib, "aether_inner"); BIND(keep_list, lib, "aether_keep_list");
    BIND(count_list, lib, "aether_count_list");
    BIND(drop_list, lib, "aether_drop_list"); BIND(parse_size, lib, "aether_parse_size");
    BIND(str_release, lib, "aether_accts_string_release"); BIND(hooks, lib, "hooks_set");
    BIND(acct_new, rt, "aether_exec_account_new"); BIND(acct_free, rt, "aether_exec_account_free");
    BIND(acct_use, rt, "aether_exec_use"); BIND(acct_used, rt, "aether_exec_account_used");
    BIND(acct_tripped, rt, "aether_exec_account_tripped"); BIND(outcome, rt, "aether_last_outcome");
    BIND(caps_used, rt, "aether_caps_used_bytes"); BIND(fail_after, rt, "aether_test_fail_alloc_after");
    return 0;
}
#endif

static AetherExecAccount* make_account(uint64_t bytes, int64_t ms, int counts, AetherExecAccount* parent) {
    AetherExecLimits l = { bytes, ms, counts, parent };
    return acct_new(&l);
}
static void use(AetherExecAccount* a) { acct_use(a, NULL); }

/* nested: the service runs inner under account g_b and leaves it in use. */
static AetherExecAccount* g_b;
static int g_inner_outcome;
static void service(int which) {
    (void)which;
    acct_use(g_b, NULL);
    (void)inner(10);
    g_inner_outcome = outcome();
}

static AetherExecAccount* g_shared;
static int g_thread_rc;
static void* other_thread(void* arg) {
    (void)arg;
    g_thread_rc = acct_use(g_shared, NULL);
    return NULL;
}

int main(int argc, char** argv) {
    if (load(argc, argv) != 0) return 1;
    hooks(service);
    /* What each kind of call allocates once and keeps (a parser's caches), made
     * before the count the last line compares with. */
    (void)grow(2); (void)count_list(2); (void)parse_size("[1]"); drop_list(keep_list(2));
    uint64_t base = caps_used();

    /* isolated + kept + credit */
    AetherExecAccount* A = make_account(128 * 1024, 0, 0, NULL);
    AetherExecAccount* B = make_account(0, 0, 0, NULL);
    use(A);
    const void* kept = hand_over(2048);           /* 32 KiB, A's while the host holds it */
    int o1 = outcome();
    uint64_t a_after_kept = acct_used(A);
    use(B);
    int b1 = grow(100);
    int ob1 = outcome();
    uint64_t a_during_b = acct_used(A);
    use(A);
    int a2 = grow(4000);                          /* 64 KiB more, 128 at its peak: past what A has left */
    int oa2 = outcome();
    int ta2 = acct_tripped(A);
    use(B);
    int b2 = grow(3000);
    int ob2 = outcome();
    use(NULL);
    int h = grow(10);
    int oh = outcome();
    printf("isolated: A %d outcome %d tripped %d; B %d outcome %d; host %d outcome %d\n",
           a2, oa2, ta2, b2, ob2, h, oh);
    printf("kept: hand_over outcome %d, A holds it (%s), unchanged while B ran (%s); B %d outcome %d\n",
           o1, a_after_kept >= 2048 * 16 ? "yes" : "no", a_during_b == a_after_kept ? "yes" : "no", b1, ob1);
    use(B);
    void* list = keep_list(50);                   /* B's list */
    use(A);
    int dropped = drop_list(list);                /* freed under A: credits B */
    uint64_t b_after_drop = acct_used(B);
    use(NULL);
    str_release(kept);                            /* freed by the host: credits A */
    printf("credit: B's list freed under A (%d items) leaves B %llu; A's string freed by the host leaves A %llu\n",
           dropped, (unsigned long long)b_after_drop, (unsigned long long)acct_used(A));

    /* narrow */
    AetherExecAccount* P = make_account(64 * 1024, 0, 0, NULL);
    AetherExecAccount* C = make_account(1024 * 1024, 0, 0, P);
    use(C);
    const void* held = hand_over(1024);           /* 16 KiB, charged to C and P */
    uint64_t p_after = acct_used(P);
    int c2 = grow(2048);                          /* 32 KiB, 64 at its peak: C allows it, P has 48 left */
    int oc2 = outcome();
    use(NULL);
    str_release(held);
    printf("narrow: the child's 16 KiB counted against its parent (%s); past the parent's limit %d outcome %d; freed, parent %llu child %llu\n",
           p_after >= 1024 * 16 ? "yes" : "no", c2, oc2,
           (unsigned long long)acct_used(P), (unsigned long long)acct_used(C));

    /* std */
    AetherExecAccount* S = make_account(8 * 1024, 0, 0, NULL);
    size_t n = 20000;
    char* doc = (char*)malloc(n * 2 + 2);
    if (!doc) return 1;
    doc[0] = '[';
    for (size_t i = 0; i < n; i++) { doc[1 + 2 * i] = '0'; doc[2 + 2 * i] = ','; }
    doc[2 * n] = ']';
    doc[2 * n + 1] = '\0';
    use(S);
    int js = parse_size(doc);
    int ojs = outcome();
    int big = count_list(2000);
    int ol = outcome();
    use(NULL);
    int small = parse_size("[1,2,3]");
    printf("std: JSON past the allowance %d outcome %d; list past it %d outcome %d; outside it %d\n",
           js, ojs, big, ol, small);
    free(doc);

    /* inject */
    use(B);
    fail_after(2);
    int fi = grow(10);
    int ofi = outcome();
    use(NULL);
    printf("inject: %d outcome %d\n", fi, ofi);

    /* deadline */
    AetherExecAccount* D = make_account(0, 30, AETHER_DEADLINE_ELAPSED, NULL);
    use(D);
    int d1 = spin(2000000000);
    int od1 = outcome();
    use(B);
    int d2 = spin(1000);
    int od2 = outcome();
    use(NULL);
    printf("deadline: D %d outcome %d tripped %d; B %d outcome %d tripped %d\n",
           d1, od1, acct_tripped(D), d2, od2, acct_tripped(B));

    /* active */
    AetherExecAccount* E = make_account(0, 200, AETHER_DEADLINE_ACTIVE, NULL);
    AetherExecAccount* F = make_account(0, 200, AETHER_DEADLINE_ELAPSED, NULL);
    sleep_ms(300);                                /* suspended: E's budget is untouched */
    use(E);
    int e1 = spin(1000);
    int oe1 = outcome();
    use(F);
    int f1 = spin(1000);
    int of1 = outcome();
    use(E);
    int e2 = spin(2000000000);
    int oe2 = outcome();
    use(NULL);
    printf("active: after 300 ms away, ACTIVE %d outcome %d, ELAPSED %d outcome %d; ACTIVE spent %d outcome %d\n",
           e1, oe1, f1, of1, e2, oe2);

    /* nested */
    g_b = B;
    use(A);
    int ou = outer(1);
    int oo = outcome();
    AetherExecAccount* in_use = NULL;
    acct_use(NULL, &in_use);
    printf("nested: outer %d outcome %d, inner outcome %d; in use after: %s\n", ou, oo, g_inner_outcome,
           in_use == A ? "A" : in_use == B ? "B" : "other");

    /* thread */
    g_shared = A;
    use(A);
    pthread_t t;
    if (pthread_create(&t, NULL, other_thread, NULL) != 0) return 1;
    pthread_join(t, NULL);
    use(NULL);
    int again = acct_use(A, NULL);
    use(NULL);
    printf("thread: another thread %d; this thread later %d\n", g_thread_rc, again);

    acct_free(A); acct_free(B); acct_free(C); acct_free(P); acct_free(S);
    acct_free(D); acct_free(E); acct_free(F);
    printf("baseline: %s\n", caps_used() == base ? "yes" : "no");
    fflush(stdout);
    return 0;
}
