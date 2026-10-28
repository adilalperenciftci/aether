/* The freed-memory probe of test_key_wipe.sh (#3382), in C: blocks from the
 * C allocator as it hands them out, uninitialised, which is what a freed
 * key copy would reach. (Aether's own allocations come back zeroed, so they
 * cannot show what a block held before.)
 *
 * key_probe_supported() is 0 where reading such a block is itself an error
 * or proves nothing: under Valgrind's memcheck, MemorySanitizer and
 * AddressSanitizer (whose quarantine keeps freed blocks back). */
#include <stdlib.h>
#include <string.h>

#if defined(__has_feature)
#  if __has_feature(memory_sanitizer) || __has_feature(address_sanitizer)
#    define KEY_PROBE_SANITIZER 1
#  endif
#endif
#if defined(__SANITIZE_ADDRESS__)
#  define KEY_PROBE_SANITIZER 1
#endif
#if defined(__linux__) && defined(__has_include)
#  if __has_include(<valgrind/valgrind.h>)
#    include <valgrind/valgrind.h>
#    define KEY_PROBE_VALGRIND 1
#  endif
#endif

int key_probe_supported(void) {
#ifdef KEY_PROBE_SANITIZER
    return 0;
#else
#  ifdef KEY_PROBE_VALGRIND
    if (RUNNING_ON_VALGRIND) return 0;
#  endif
    const char* pre = getenv("LD_PRELOAD");
    if (pre && strstr(pre, "vgpreload")) return 0;
    return 1;
#endif
}

/* Ask for `blocks` blocks of each power of two from `lo` to `hi` bytes (the
 * sizes std.bytes gives its buffers, which double from 16), all held until
 * the end so that none is handed out twice and the allocator's free blocks
 * of those sizes run out, largest first so that small ones do not carve up
 * a freed large block before it is looked at, look in each for the 16 bytes at `pattern`, then
 * give them all back: how many held it. */
int key_probe_scan(const unsigned char* pattern, int lo, int hi, int blocks) {
    int hits = 0;
    int sizes = 0;
    for (int s = lo; s <= hi; s *= 2) sizes++;
    size_t count = (size_t)sizes * (size_t)blocks;
    void** held = (void**)calloc(count, sizeof(void*));
    if (!held) return -1;
    size_t at = 0;
    for (int size = hi; size >= lo; size /= 2) {
        for (int k = 0; k < blocks; k++) {
            unsigned char* p = (unsigned char*)malloc((size_t)size);
            held[at++] = p;
            if (!p) continue;
            for (int i = 0; i + 16 <= size; i++) {
                if (p[i] == pattern[0] && memcmp(p + i, pattern, 16) == 0) hits++;
            }
        }
    }
    for (size_t j = 0; j < at; j++) free(held[j]);
    free(held);
    return hits;
}
