/* A C host with its own runtime, which loads a library exporting a sandbox
 * rendezvous of another layout first (#2957). Its copy refuses to share
 * levels with it, says so once on stderr, enforces its own, and never calls
 * the foreign one.
 *
 *   before: 1 / in a deny-all level: 0 / after: 1 / foreign levels called: 0
 */
#include <stdio.h>
#include "aether_sandbox.h"
#ifdef _WIN32
#include <windows.h>
static void* load(const char* p) { return (void*)LoadLibraryA(p); }
static void* sym(void* h, const char* n) { return (void*)GetProcAddress((HMODULE)h, n); }
#else
#include <dlfcn.h>
static void* load(const char* p) { return dlopen(p, RTLD_NOW | RTLD_GLOBAL); }
static void* sym(void* h, const char* n) { return dlsym(h, n); }
#endif

extern void* list_new(void);
extern void list_free(void* l);

int main(int argc, char** argv) {
    void* h = argc < 2 ? NULL : load(argv[1]);
    int (*calls)(void) = h ? (int (*)(void))sym(h, "foreign_sbx_calls") : NULL;
    if (!calls) { printf("cannot load the foreign library\n"); return 1; }
    printf("before: %d\n", aether_sandbox_check("env", "PATH"));
    void* nothing = list_new();
    aether_sandbox_push(nothing);
    printf("in a deny-all level: %d\n", aether_sandbox_check("env", "PATH"));
    aether_sandbox_pop();
    list_free(nothing);
    printf("after: %d\n", aether_sandbox_check("env", "PATH"));
    printf("foreign levels called: %d\n", calls());
    fflush(stdout);
    return 0;
}
