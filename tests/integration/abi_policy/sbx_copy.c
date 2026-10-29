/* A runtime copy in a library (#2957, #3437), which sbx_driver.c loads after
 * a library exporting a sandbox rendezvous of another layout. Its copy
 * refuses to share levels with it, says so once on stderr, enforces its own,
 * and never calls the foreign one.
 *
 * In a library, not in the host program: where executables export their
 * symbols (macOS), a program that links the runtime is the first image a
 * copy looks in, so its own rendezvous was found and the foreign one never
 * read.
 *
 *   before: 1 / in a deny-all level: 0 / after: 1 / foreign levels called: 0
 */
#include <stdio.h>
#include "aether_sandbox.h"
#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

extern void* list_new(void);
extern void list_free(void* l);

EXPORT void sbx_run(int (*calls)(void)) {
    printf("before: %d\n", aether_sandbox_check("env", "PATH"));
    void* nothing = list_new();
    aether_sandbox_push(nothing);
    printf("in a deny-all level: %d\n", aether_sandbox_check("env", "PATH"));
    aether_sandbox_pop();
    list_free(nothing);
    printf("after: %d\n", aether_sandbox_check("env", "PATH"));
    printf("foreign levels called: %d\n", calls());
    fflush(stdout);
}
