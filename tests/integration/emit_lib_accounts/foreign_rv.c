/* A library that exports a rendezvous of another layout (#2954): a later
 * version of the accounts, say. A copy that finds it first reads its
 * version and size, refuses, and never reads or writes the rest. */
#include <stdint.h>
#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

static const struct { uint32_t version, size, account_size, limits_size; } g_foreign = { 99, 16, 0, 0 };

EXPORT const void* aether_accounts_rendezvous(void) {
    return &g_foreign;
}
