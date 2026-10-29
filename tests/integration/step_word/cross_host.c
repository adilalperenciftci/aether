/* A C host with a runtime of its own (#3419), loading cross.ae's library
 * with another. The library's actor has it enter a deny-all sandbox level
 * of the host's copy, on the actor's core thread, sends to an idle actor of
 * that core, which is stepped inside the send, inside the host's level, and
 * has it leave. argv[2] is 1 when the library looks the levels up before
 * (it reads PATH first), 0 when it does not. argv[3], when given, is a third
 * copy loaded before the library (#3438): the host's first push then finds
 * that copy's count, which neither the host nor the library owns, and the
 * library must join it before its first step.
 *
 *   cross: the host's own check inside its block 0; the actor was stepped
 *   inside it, and read PATH 1 */
#include <stdio.h>
#include <stdlib.h>
#include "aether_sandbox.h"
#ifdef _WIN32
#include <windows.h>
static void* lib_open(const char* p) { return (void*)LoadLibraryA(p); }
static void* lib_sym(void* h, const char* n) { return (void*)GetProcAddress((HMODULE)h, n); }
#else
#include <dlfcn.h>
static void* lib_open(const char* p) { return dlopen(p, RTLD_NOW | RTLD_LOCAL); }
static void* lib_sym(void* h, const char* n) { return dlsym(h, n); }
#endif

extern void* list_new(void);
extern void list_free(void* l);

typedef void (*set_hooks_fn)(void (*)(void), void (*)(void));
typedef int (*start_fn)(int);

static void* g_nothing;
static int g_inside = -1;

static void host_enter(void) {
    g_nothing = list_new();
    aether_sandbox_push(g_nothing);
    g_inside = aether_sandbox_check("env", "PATH");
}

static void host_leave(void) {
    aether_sandbox_pop();
    list_free(g_nothing);
}

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: cross_host <library> <look_first> [<loaded first>]\n"); return 2; }
    if (argc > 3 && !lib_open(argv[3])) { printf("cannot load %s\n", argv[3]); return 2; }
    void* h = lib_open(argv[1]);
    if (!h) { printf("cannot load %s\n", argv[1]); return 2; }
    set_hooks_fn set_hooks = (set_hooks_fn)lib_sym(h, "cross_set_hooks");
    start_fn start = (start_fn)lib_sym(h, "aether_start");
    if (!set_hooks || !start) { printf("missing a symbol\n"); return 2; }
    set_hooks(host_enter, host_leave);
    int r = start(atoi(argv[2]));
    printf("cross: the host's own check inside its block %d; the actor %s inside it, and read PATH %d\n",
           g_inside, (r / 10) % 10 == 1 ? "was stepped" : "was not stepped", r % 10);
    fflush(stdout);
    return 0;
}
