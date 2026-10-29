/* Constant-time harness shim (ctgrind style; see test_crypto_ct_valgrind.sh).
 *
 * ct_shim_secret marks a buffer's bytes undefined for Valgrind's memcheck.
 * memcheck then reports every conditional jump, and every memory address,
 * computed from those bytes: exactly the secret-dependent branches and
 * table indexes a constant-time implementation must not have. A value the
 * code is entitled to branch on (a signature's retry decision, an AEAD tag
 * verdict) goes through std.cryptography.ct.declassify, whose hook,
 * ct_shim_declassify, marks it defined again.
 *
 * Without Valgrind's headers (any platform but Linux with valgrind
 * installed) every call is a no-op and ct_shim_available() is 0, so the probe
 * still runs as a functional test. */
#if defined(__linux__) && defined(__has_include)
#  if __has_include(<valgrind/memcheck.h>)
#    include <valgrind/memcheck.h>
#    define CT_SHIM_VALGRIND 1
#  endif
#endif

int ct_shim_available(void) {
#ifdef CT_SHIM_VALGRIND
    return RUNNING_ON_VALGRIND ? 1 : 0;
#else
    return 0;
#endif
}

void ct_shim_secret(void *p, int n) {
#ifdef CT_SHIM_VALGRIND
    if (p && n > 0) VALGRIND_MAKE_MEM_UNDEFINED(p, (unsigned long)n);
#else
    (void)p; (void)n;
#endif
}

void ct_shim_public(void *p, int n) {
#ifdef CT_SHIM_VALGRIND
    if (p && n > 0) VALGRIND_MAKE_MEM_DEFINED(p, (unsigned long)n);
#else
    (void)p; (void)n;
#endif
}

/* The declassify hook: v's stack slot is marked defined, and the value is
 * read back from it (the client request's memory clobber makes the compiler
 * store v before and reload it after). */
static int ct_shim_declassify(int v) {
#ifdef CT_SHIM_VALGRIND
    VALGRIND_MAKE_MEM_DEFINED(&v, sizeof v);
#endif
    return v;
}

void *ct_shim_declassify_hook(void) {
    return (void *)ct_shim_declassify;
}
