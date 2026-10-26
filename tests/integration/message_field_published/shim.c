/* Reads a string's header for the probe: whether its count is the atomic,
 * published one (#2919, #3192). */
#include "aether_string.h"

/* 1 for a published counted string, 0 for a plain-counted one, -1 for
 * anything else (a literal, a C string). */
int probe_published(const void* s) {
    if (!s) return -1;
    const AetherString* h = (const AetherString*)s;
    if (h->magic != AETHER_STRING_MAGIC || h->ref_count == AETHER_STRING_PINNED_REFS) return -1;
    return (h->ref_count & AETHER_STRING_SHARED_BIT) ? 1 : 0;
}
