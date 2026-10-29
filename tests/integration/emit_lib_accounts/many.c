/* #3411: more runtime copies share the accounts than the list of them once
 * held (64). argv[1] (A) is loaded first and holds the accounts; the rest
 * are the same library under other names, each making one call, so each
 * copy joins A's accounts. With an account in use, the last copy's
 * allocation is charged to it: that copy too was told an account exists.
 *
 *   many: 70 copies joined; the last one's string charged: yes, freed: yes */
#include <stdio.h>
#include <stdint.h>
#ifdef _WIN32
#include <windows.h>
static void* lib_open(const char* p) { return (void*)LoadLibraryA(p); }
static void* lib_sym(void* h, const char* n) { return (void*)GetProcAddress((HMODULE)h, n); }
#else
#include <dlfcn.h>
static void* lib_open(const char* p) { return dlopen(p, RTLD_NOW | RTLD_LOCAL); }
static void* lib_sym(void* h, const char* n) { return dlsym(h, n); }
#endif

typedef struct AetherExecAccount AetherExecAccount;
typedef struct {
    uint64_t memory_bytes;
    int64_t deadline_ms;
    int deadline_counts;
    AetherExecAccount* parent;
} Limits;
typedef int (*int_fn)(int);
typedef const void* (*str_fn)(int);
typedef void (*release_fn)(const void*);
typedef AetherExecAccount* (*new_fn)(const Limits*);
typedef void (*free_fn)(AetherExecAccount*);
typedef int (*use_fn)(AetherExecAccount*, AetherExecAccount**);
typedef uint64_t (*used_fn)(const AetherExecAccount*);

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: many <A> <B>...\n"); return 2; }
    void* a = lib_open(argv[1]);
    if (!a) { printf("cannot load %s\n", argv[1]); return 2; }
    new_fn account_new = (new_fn)lib_sym(a, "aether_exec_account_new");
    free_fn account_free = (free_fn)lib_sym(a, "aether_exec_account_free");
    use_fn use = (use_fn)lib_sym(a, "aether_exec_use");
    used_fn used = (used_fn)lib_sym(a, "aether_exec_account_used");
    void* last = NULL;
    int joined = 0;
    for (int i = 2; i < argc; i++) {
        void* b = lib_open(argv[i]);
        int_fn grow = b ? (int_fn)lib_sym(b, "aether_grow") : NULL;
        if (!grow) { printf("cannot load %s\n", argv[i]); return 2; }
        if (grow(1) == 16) joined++;
        last = b;
    }
    str_fn hand_over = (str_fn)lib_sym(last, "aether_hand_over");
    release_fn release = (release_fn)lib_sym(last, "aether_accts_string_release");
    Limits l = { 1 << 20, 0, 0, NULL };
    AetherExecAccount* acc = account_new(&l);
    use(acc, NULL);
    const void* s = hand_over(4);
    uint64_t held = used(acc);
    release(s);
    uint64_t after = used(acc);
    use(NULL, NULL);
    account_free(acc);
    printf("many: %d copies joined; the last one's string charged: %s, freed: %s\n", joined + 1,
           held > 0 ? "yes" : "no", held > 0 && after == 0 ? "yes" : "no");
    fflush(stdout);
    return 0;
}
