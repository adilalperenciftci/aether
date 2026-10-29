/* A library with a sandbox rendezvous of another layout (#2957), with
 * working members, which its record names as a copy of another Aether names
 * its own (aether_rv_mark.h, #3445): by default the
 * version-1 one, which had no size; with -DRV_VERSION=n a later one, with a
 * size and a member more. A copy that finds it first refuses to share
 * levels with it, says so once, and reads nothing of it but its version
 * and size: its level count is never called. */
#include <stdatomic.h>
#include <stdint.h>
#include "aether_rv_mark.h"
#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

#ifndef RV_VERSION
#define RV_VERSION 1
#endif

static atomic_int g_threads;
static atomic_int g_calls;
static _Thread_local int t_levels;

static int levels(int delta) {
    atomic_fetch_add(&g_calls, 1);
    int before = t_levels;
    t_levels += delta;
    if (before == 0 && t_levels > 0) atomic_fetch_add(&g_threads, 1);
    else if (before > 0 && t_levels == 0) atomic_fetch_sub(&g_threads, 1);
    return t_levels;
}

#if RV_VERSION == 1
static const struct { int version; atomic_int* threads; int (*levels)(int); } g_rv = {
    1, &g_threads, levels
};
#else
typedef struct {
    uint32_t version;
    uint32_t size;
    atomic_int* threads;
    int (*levels)(int);
    void* more;
} Later;
static const Later g_rv = { RV_VERSION, (uint32_t)sizeof(Later), &g_threads, levels, 0 };
#endif

__attribute__((used)) AETHER_COPY_LOCAL const void* foreign_sandbox_rendezvous(void) {
    return &g_rv;
}

AETHER_RV_MARK(foreign_sandbox_mark, AETHER_RV_KIND_SANDBOX, foreign_sandbox_rendezvous);

/* How many times a copy called this rendezvous's level count. */
EXPORT int foreign_sbx_calls(void) {
    return atomic_load(&g_calls);
}
