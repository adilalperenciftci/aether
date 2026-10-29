/* Two libraries in one process across versions (#2957): mlib.ae built by
 * the release before this Aether (argv[1], loaded first) and by this one
 * (argv[2]), each with a runtime of its own. The old copy has no execution
 * accounts and no shared facilities; the new one's work beside it.
 *
 *   typed:   calls into both, interleaved
 *   strings: each string given back to the library that made it
 *   errors:  a panic in the new library ends its call; both go on
 *   account: the new library's account charges what it holds, keeps it
 *            while suspended (the old library runs in between, charging
 *            nothing to it), refuses past its allowance when resumed, and
 *            is freed at zero
 *   unload:  both unload, the new one first
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include "libaether.h"
#include "aether_lib_meta.h"
#ifdef _WIN32
#include <windows.h>
static void* lib_open(const char* p) { return (void*)LoadLibraryA(p); }
static void* lib_sym(void* h, const char* n) { return (void*)GetProcAddress((HMODULE)h, n); }
static int lib_close(void* h) { return FreeLibrary((HMODULE)h) ? 0 : -1; }
#else
#include <dlfcn.h>
static void* lib_open(const char* p) { return dlopen(p, RTLD_NOW | RTLD_LOCAL); }
static void* lib_sym(void* h, const char* n) { return dlsym(h, n); }
static int lib_close(void* h) { return dlclose(h); }
#endif

typedef int (*add_fn)(int, int);
typedef const void* (*greet_fn)(int);
typedef void (*release_fn)(const void*);
typedef const char* (*data_fn)(const void*);
typedef int (*int_fn)(int);
typedef int (*outcome_fn)(void);
typedef const AetherLibMeta* (*meta_fn)(void);
typedef AetherExecAccount* (*new_fn)(const AetherExecLimits*);
typedef void (*free_fn)(AetherExecAccount*);
typedef int (*use_fn)(AetherExecAccount*, AetherExecAccount**);
typedef uint64_t (*used_fn)(const AetherExecAccount*);

typedef struct {
    void* h;
    add_fn add;
    greet_fn greet;
    release_fn release;
    data_fn data;
    int_fn checked, grow;
} Lib;

static void* need(void* h, const char* n) {
    void* p = lib_sym(h, n);
    if (!p) { printf("missing %s\n", n); fflush(stdout); exit(2); }
    return p;
}

static Lib load(const char* path) {
    Lib l;
    l.h = lib_open(path);
    if (!l.h) { printf("cannot load %s\n", path); fflush(stdout); exit(2); }
    l.add = (add_fn)need(l.h, "aether_add");
    l.greet = (greet_fn)need(l.h, "aether_greet");
    l.release = (release_fn)need(l.h, ((meta_fn)need(l.h, "aether_lib_meta"))()->string_release);
    l.data = (data_fn)need(l.h, "aether_string_data");
    l.checked = (int_fn)need(l.h, "aether_checked");
    l.grow = (int_fn)need(l.h, "aether_grow");
    return l;
}

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: two <old library> <new library>\n"); return 2; }
    Lib o = load(argv[1]);
    Lib n = load(argv[2]);

    printf("typed: old %d, new %d, old %d\n", o.add(1, 2), n.add(3, 4), o.add(5, 6));

    const void* so = o.greet(1);
    const void* sn = n.greet(2);
    printf("strings: %s, %s\n", o.data(so), n.data(sn));
    o.release(so);
    n.release(sn);

    outcome_fn outcome = (outcome_fn)need(n.h, "aether_last_outcome");
    int bad = n.checked(-1);
    int badc = outcome();
    printf("errors: new checked(-1) %d outcome %d; then old %d, new %d\n", bad, badc, o.checked(3), n.checked(4));

    new_fn account_new = (new_fn)need(n.h, "aether_exec_account_new");
    free_fn account_free = (free_fn)need(n.h, "aether_exec_account_free");
    use_fn use = (use_fn)need(n.h, "aether_exec_use");
    used_fn used = (used_fn)need(n.h, "aether_exec_account_used");
    AetherExecLimits lim = { 1 << 20, 0, AETHER_DEADLINE_ELAPSED, NULL };
    AetherExecAccount* a = account_new(&lim);
    AetherExecAccount* prev = NULL;
    use(a, &prev);
    const void* kept = n.greet(3);
    uint64_t held = used(a);
    use(prev, NULL);
    /* Suspended: the old library runs, charging nothing to the account. */
    const void* other = o.greet(4);
    int og = o.grow(4096);
    o.release(other);
    uint64_t while_out = used(a);
    use(a, &prev);
    int big = n.grow(1 << 17);
    int bigc = outcome();
    int small = n.grow(4);
    n.release(kept);
    uint64_t after = used(a);
    use(prev, NULL);
    account_free(a);
    printf("account: holds %s, the same while the old library ran (%d): %s; "
           "resumed, past its allowance %d outcome %d, within it %d; at zero %s, freed\n",
           held > 0 ? "bytes" : "nothing", og, while_out == held ? "yes" : "no", big, bigc, small,
           after == 0 ? "yes" : "no");

    int un = lib_close(n.h);
    int still = o.add(7, 8);
    int uo = lib_close(o.h);
    printf("unload: new %d, old still works %d, old %d\n", un, still, uo);
    fflush(stdout);
    return 0;
}
