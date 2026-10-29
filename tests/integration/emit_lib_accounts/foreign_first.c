/* Accounts of another layout loaded first (#2954, #3437). A host with no
 * runtime of its own loads argv[1] (foreign_rv: a rendezvous of another
 * layout), then two copies of the accounts library, argv[2] and argv[3].
 * Each copy finds the foreign rendezvous first, refuses accounts and says so
 * once, and its calls still work.
 *
 * The host has no runtime because a program that links the runtime is the
 * first image a copy looks in where executables export their symbols
 * (macOS): there two_copies, which this case was part of, found its own
 * accounts first and never read the foreign ones.
 *
 *   foreign: the first copy refused, the second refused; a call still works: 160 outcome 0 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
static void* lib_open(const char* p) { return (void*)LoadLibraryA(p); }
static void* lib_sym(void* h, const char* n) {
    FARPROC f = GetProcAddress((HMODULE)h, n);
    void* v;
    memcpy(&v, &f, sizeof(v));
    return v;
}
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
typedef int (*outcome_fn)(void);
typedef AetherExecAccount* (*new_fn)(const Limits*);

int main(int argc, char** argv) {
    if (argc < 4) { printf("usage: foreign_first <foreign rv> <library> <its copy>\n"); return 2; }
    if (!lib_open(argv[1])) { printf("cannot load %s\n", argv[1]); return 2; }
    void* a = lib_open(argv[2]);
    void* b = lib_open(argv[3]);
    if (!a || !b) { printf("cannot load the libraries\n"); return 2; }
    void* pa = lib_sym(a, "aether_exec_account_new");
    void* pb = lib_sym(b, "aether_exec_account_new");
    void* pg = lib_sym(b, "aether_grow");
    void* po = lib_sym(b, "aether_last_outcome");
    if (!pa || !pb || !pg || !po) { printf("missing a symbol\n"); return 2; }
    new_fn new_a, new_b;
    int_fn grow;
    outcome_fn outcome;
    memcpy(&new_a, &pa, sizeof(pa));
    memcpy(&new_b, &pb, sizeof(pb));
    memcpy(&grow, &pg, sizeof(pg));
    memcpy(&outcome, &po, sizeof(po));
    Limits l = { 64 * 1024, 0, 0, NULL };
    AetherExecAccount* first = new_a(&l);
    AetherExecAccount* second = new_b(&l);
    int r = grow(10);
    printf("foreign: the first copy %s, the second %s; a call still works: %d outcome %d\n",
           first ? "made one" : "refused", second ? "made one" : "refused", r, outcome());
    fflush(stdout);
    return 0;
}
