/* Two runtime copies in one C host (#2954): this program links the runtime
 * (one copy) and loads the library built with a runtime of its own (the
 * other). A copy finds the accounts once, in the first loaded image that
 * has them: this program, first in load order, by its record, though it
 * exports nothing on Windows, nor on Linux without -rdynamic (#3445).
 *
 *   two_copies <lib>          the library loaded before the first account
 *                             call: an account made and put in use through
 *                             this program's copy is charged what either
 *                             copy allocates, and is refused on another
 *                             thread whichever copy asks.
 *   two_copies <lib> early    an account made before the library loaded:
 *                             the library's copy finds this program's
 *                             accounts and shares it (#3445: it found its
 *                             own, and refused it).
 *   two_copies <lib> in_use   an account made and put in use before the
 *                             library loaded: what the library allocates is
 *                             charged to it (#3445: to nothing).
 *
 * Accounts of another layout loaded first are foreign_first.c's (#3437):
 * where an executable exports its symbols (macOS), this program's own
 * accounts are the first a copy finds, and a foreign one is never read. */
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include "libaether.h"
#include "aether_resource_caps.h"
#ifdef _WIN32
#include <windows.h>
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
static lib_t lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void* lib_sym(lib_t h, const char* name) { return dlsym(h, name); }
#endif

typedef int (*int_fn)(int);
typedef int (*use_fn)(AetherExecAccount*, AetherExecAccount**);
typedef int (*outcome_fn)(void);

static int_fn grow;
static use_fn lib_use;
static outcome_fn lib_outcome;

static int bind_lib(lib_t lib) {
    void* p;
    if (!(p = lib_sym(lib, "aether_grow"))) return 0;
    memcpy(&grow, &p, sizeof(p));
    if (!(p = lib_sym(lib, "aether_exec_use"))) return 0;
    memcpy(&lib_use, &p, sizeof(p));
    if (!(p = lib_sym(lib, "aether_last_outcome"))) return 0;
    memcpy(&lib_outcome, &p, sizeof(p));
    return 1;
}

static AetherExecAccount* g_a;
static int g_mine, g_theirs;
static void* other(void* arg) {
    (void)arg;
    g_mine = aether_exec_use(g_a, NULL);
    g_theirs = lib_use(g_a, NULL);
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) { printf("usage: two_copies <library> [early|in_use]\n"); return 1; }
    int early = argc > 2 && strcmp(argv[2], "early") == 0;
    int in_use = argc > 2 && strcmp(argv[2], "in_use") == 0;
    AetherExecLimits l = { 64 * 1024, 0, AETHER_DEADLINE_ELAPSED, NULL };
    if (early || in_use) g_a = aether_exec_account_new(&l);
    if (in_use) aether_exec_use(g_a, NULL);
    lib_t lib = lib_open(argv[1]);
    if (!lib || !bind_lib(lib)) { printf("cannot load %s\n", argv[1]); return 1; }

    if (early) {
        /* Shared: one account in use for the thread, so this copy sees the
         * one the library's copy put in use, and charged what the library
         * allocates past it. */
        int rc = lib_use(g_a, NULL);
        int r = grow(4000);
        int out = lib_outcome();
        int charged = aether_exec_account_tripped(g_a) != 0;
        AetherExecAccount* seen = NULL;
        if (rc == 0) aether_exec_use(NULL, &seen);
        int ok = rc == 0 && seen == g_a && out == AETHER_MEMORY_CAP && charged;
        printf("early: the library's copy shares the account: %s\n", ok ? "yes" : "no");
        if (!ok) printf("  (use %d, seen here %s, grow %d outcome %d, tripped %d)\n",
                        rc, seen == g_a ? "yes" : "no", r, out, charged);
        if (rc == 0) lib_use(NULL, NULL);
        aether_exec_account_free(g_a);
        return 0;
    }
    if (in_use) {
        /* The library's first call finds the accounts: this program's, with
         * the account it put in use, which the library's allocations past
         * the allowance trip. */
        int r = grow(4000);
        int out = lib_outcome();
        int charged = aether_exec_account_tripped(g_a) != 0;
        int ok = out == AETHER_MEMORY_CAP && charged && r == 0;
        printf("in use: the library's allocations are charged to the account in use: %s\n",
               ok ? "yes" : "no");
        if (!ok) printf("  (grow %d outcome %d, tripped %d)\n", r, out, charged);
        aether_exec_use(NULL, NULL);
        aether_exec_account_free(g_a);
        return 0;
    }

    g_a = aether_exec_account_new(&l);
    aether_exec_use(g_a, NULL);
    uint64_t before = aether_exec_account_used(g_a);
    void* p = aether_caps_malloc(1000);
    uint64_t mine = aether_exec_account_used(g_a) - before;
    aether_caps_free(p, 1000);
    int r = grow(4000);
    printf("shared: this copy's 1000 bytes charged %llu; the library's past the allowance %d outcome %d, tripped %d\n",
           (unsigned long long)mine, r, lib_outcome(), aether_exec_account_tripped(g_a));
    pthread_t t;
    if (pthread_create(&t, NULL, other, NULL) != 0) return 1;
    pthread_join(t, NULL);
    printf("thread: in use here, refused on another through this copy %d, through the library's %d; holds %llu\n",
           g_mine, g_theirs, (unsigned long long)aether_exec_account_used(g_a));
    aether_exec_use(NULL, NULL);
    aether_exec_account_free(g_a);
    fflush(stdout);
    return 0;
}
