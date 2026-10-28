#ifndef AETHER_WIPE_H
#define AETHER_WIPE_H

#include <stddef.h>
#include <string.h>

/* Zero n bytes at p so that the writes happen, even right before the memory
 * is freed (#3376). A plain memset there is a dead store the compiler may
 * drop. This one is called through a volatile function pointer: the
 * compiler must load the pointer when the call runs, so it cannot know the
 * callee is memset or prove its writes dead, whatever it inlines or links
 * together. OpenSSL's OPENSSL_cleanse uses the same technique, and it needs
 * nothing from the platform (no explicit_bzero, memset_s or
 * SecureZeroMemory), so it works for every target the runtime builds for. */
static inline void aether_wipe(void* p, size_t n) {
    static void* (*const volatile wipe_memset)(void*, int, size_t) = memset;
    if (p && n) wipe_memset(p, 0, n);
}

#endif
