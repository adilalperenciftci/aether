/* #3411: a library with a runtime of its own that is unloaded leaves
 * nothing of it in the accounts it shared. argv[1] (A) is loaded first and
 * holds the accounts; argv[2] (B, the same library under another name)
 * makes one call, so its copy finds A's accounts and registers its
 * allocation fast-path word with them, and is unloaded. Then A makes and
 * frees the first account, which marks the word of every copy registered
 * with it: B's no more, its image gone.
 *
 *   unload: B's call 160, unloaded 0; an account made and freed after: yes */
#include <stdio.h>
#include <stdint.h>
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

typedef struct AetherExecAccount AetherExecAccount;
typedef struct {
    uint64_t memory_bytes;
    int64_t deadline_ms;
    int deadline_counts;
    AetherExecAccount* parent;
} Limits;
typedef int (*int_fn)(int);
typedef AetherExecAccount* (*new_fn)(const Limits*);
typedef void (*free_fn)(AetherExecAccount*);
typedef int (*use_fn)(AetherExecAccount*, AetherExecAccount**);

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: unload <A> <B>\n"); return 2; }
    void* a = lib_open(argv[1]);
    void* b = lib_open(argv[2]);
    if (!a || !b) { printf("cannot load the libraries\n"); return 2; }
    new_fn account_new = (new_fn)lib_sym(a, "aether_exec_account_new");
    free_fn account_free = (free_fn)lib_sym(a, "aether_exec_account_free");
    use_fn use = (use_fn)lib_sym(a, "aether_exec_use");
    int_fn grow_b = (int_fn)lib_sym(b, "aether_grow");
    int_fn grow_a = (int_fn)lib_sym(a, "aether_grow");
    if (!account_new || !account_free || !use || !grow_b || !grow_a) { printf("missing a symbol\n"); return 2; }
    int got = grow_b(10);
    int closed = lib_close(b);
    Limits l = { 1 << 20, 0, 0, NULL };
    AetherExecAccount* acc = account_new(&l);
    int ok = acc != NULL && use(acc, NULL) == 0 && grow_a(10) == 160 && use(NULL, NULL) == 0;
    account_free(acc);
    printf("unload: B's call %d, unloaded %d; an account made and freed after: %s\n", got, closed, ok ? "yes" : "no");
    fflush(stdout);
    return 0;
}
