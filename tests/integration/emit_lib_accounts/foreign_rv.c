/* A library with a rendezvous of another layout (#2954): a later version
 * of the accounts, say, which its record names as a copy of another Aether
 * names its own (aether_rv_mark.h, #3445). A copy that finds it first reads
 * its version and size, refuses, and never reads or writes the rest. */
#include <stdint.h>
#include "aether_rv_mark.h"

static const struct { uint32_t version, size, account_size, limits_size; } g_foreign = { 99, 16, 0, 0 };

AETHER_RV_FN const void* foreign_accounts_rendezvous(void) {
    return &g_foreign;
}

AETHER_RV_MARK(foreign_accounts_mark, AETHER_RV_KIND_ACCOUNTS, foreign_accounts_rendezvous);
