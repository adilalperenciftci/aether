/* The OS CSPRNG, failing on request (#3293; see test_random_failure.sh).
 *
 * std.cryptography draws its random bytes from the OS: BCryptGenRandom on
 * Windows, getrandom(2) on Linux. This file, linked into rngfail.ae
 * (aether.toml), puts itself in front of that call: rng_fail_after(n)
 * lets n more calls through and fails every one after, as a CSPRNG that
 * stops working would; rng_fail_after(-1) never fails. On Windows the
 * library calls BCryptGenRandom through its import pointer, and this file
 * defines both (so the linker takes them before bcrypt's); on Linux
 * this getrandom comes before libc's. Elsewhere (macOS and the BSDs use
 * arc4random_buf, which cannot fail) nothing is replaced and
 * rng_fail_supported() is 0. */
#if defined(__linux__)
#define _GNU_SOURCE /* syscall(2) in unistd.h */
#endif
#include <stddef.h>

static int g_allow = -1;   /* calls left before failing; -1: never fail */
static int g_calls = 0;    /* calls seen, failed or not */

void rng_fail_after(int n) { g_allow = n; }
int rng_fail_calls(void) { return g_calls; }

/* 1 when this call must fail. */
static int rng_fail_now(void) {
    g_calls++;
    if (g_allow < 0) return 0;
    if (g_allow == 0) return 1;
    g_allow--;
    return 0;
}

#if defined(_WIN32)
#include <windows.h>
typedef long (WINAPI *gen_fn)(void *alg, unsigned char *buf, unsigned long n, unsigned long flags);

long WINAPI BCryptGenRandom(void *alg, unsigned char *buf, unsigned long n, unsigned long flags) {
    static gen_fn real = NULL;
    if (rng_fail_now()) return (long)0xC0000001L; /* STATUS_UNSUCCESSFUL */
    if (!real) real = (gen_fn)(void *)GetProcAddress(LoadLibraryA("bcrypt.dll"), "BCryptGenRandom");
    return real ? real(alg, buf, n, flags) : (long)0xC0000001L;
}

/* Both names, so the linker needs nothing from bcrypt's import library: the
 * thunk for a direct call, the pointer for a dllimport one. */
gen_fn __imp_BCryptGenRandom = BCryptGenRandom;

int rng_fail_supported(void) { return 1; }
#elif defined(__linux__)
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

ssize_t getrandom(void *buf, size_t n, unsigned int flags) {
    if (rng_fail_now()) {
        errno = EIO;
        return -1;
    }
    return (ssize_t)syscall(SYS_getrandom, buf, n, flags);
}

int rng_fail_supported(void) { return 1; }
#else
int rng_fail_supported(void) { return 0; }
#endif
