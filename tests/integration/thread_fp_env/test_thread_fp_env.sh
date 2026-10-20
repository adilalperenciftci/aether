#!/bin/sh
# Regression (#3027): a thread Aether starts has its creator's floating-point
# state.
#
# On Windows the pthread_create shim over CreateThread gave every thread
# Windows' default x87 control word, 53-bit precision (0x027f), while
# MinGW's startup runs the main thread at 64-bit (0x037f). MinGW's libm
# sqrt is the x87 fsqrt, which rounds twice at 64-bit precision, so the same
# call gave different bits on a std.worker thread than on main (253 of a
# million inputs), and aephysics' four-worker runs at -O0 changed from run
# to run as work stealing moved blocks between threads.
#
# The C side records, on the main thread and then inside a std.worker job,
# the x87 control word, the MXCSR's control bits and a hash of a million
# library sqrt results (called through a pointer, so the library runs at
# any -O). All three must match. Off x86 (or without GCC/Clang) the registers read -1 on
# both sides and only the hash is compared.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] thread_fp_env: ae not built"; exit 0; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP" || :; return 0; }
trap cleanup EXIT
AETHER_CACHE_DIR="$TMP/cache"
export AETHER_CACHE_DIR

mkdir -p "$TMP/p"
cat > "$TMP/p/shim.c" <<'COF'
#include <math.h>
#include <stdint.h>
#include <string.h>

static double (*volatile lib_sqrt)(double) = sqrt;
static long long rec[2][3];

static long long fp_cw(void) {
#if (defined(__GNUC__) || defined(__clang__)) && (defined(__x86_64__) || defined(__i386__))
    unsigned short cw;
    __asm__ volatile ("fnstcw %0" : "=m"(cw));
    return cw;
#else
    return -1;
#endif
}

/* The MXCSR's controls; its sticky exception flags (bits 0-5) record what
 * this thread has computed so far, not its state. */
static long long fp_mxcsr(void) {
#if (defined(__GNUC__) || defined(__clang__)) && defined(__SSE__)
    unsigned int mx;
    __asm__ volatile ("stmxcsr %0" : "=m"(mx));
    return mx & ~0x3fu;
#else
    return -1;
#endif
}

static long long sqrt_hash(void) {
    uint64_t state = 88172645463325252ull, h = 1469598103934665603ull;
    for (int i = 0; i < 1000000; ++i) {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17;
        double x = (double)(state >> 11) * (1.0 / 9007199254740992.0) * 1000.0;
        double r = lib_sqrt(x);
        uint64_t bits;
        memcpy(&bits, &r, 8);
        h = (h ^ bits) * 1099511628211ull;
    }
    return (long long)h;
}

/* Records this thread's state in slot 0 (main) or 1 (worker). */
void ae_fp_record(int slot) {
    rec[slot][0] = fp_cw();
    rec[slot][1] = fp_mxcsr();
    rec[slot][2] = sqrt_hash();
}

/* 1 when what (0 control word, 1 MXCSR, 2 sqrt hash) matches across the two. */
int ae_fp_same(int what) { return rec[0][what] == rec[1][what]; }
COF
cat > "$TMP/p/main.ae" <<'AEOF'
import std.worker

extern ae_fp_record(slot: int)
extern ae_fp_same(what: int) -> int

main() {
    ae_fp_record(0)
    worker.pool_size(2)
    ok = worker.run(| _ctx: ptr | {
        ae_fp_record(1)
    }, | _ctx: ptr | {})
    if !ok {
        println("could not queue")
        return
    }
    worker.wait()
    worker.drain(16)
    println("control word same ${ae_fp_same(0) == 1}")
    println("mxcsr same ${ae_fp_same(1) == 1}")
    println("sqrt same ${ae_fp_same(2) == 1}")
    worker.pool_shutdown()
}
AEOF
printf '[[bin]]\nname = "app"\npath = "main.ae"\nextra_sources = ["shim.c"]\n' > "$TMP/p/aether.toml"

if ! (cd "$TMP/p" && "$AE" build main.ae -o ./app >build.log 2>&1); then
    echo "  [FAIL] thread_fp_env: the program did not build"
    grep -v '^\[' "$TMP/p/build.log" | sed 's/^/        /' | head -10
    exit 1
fi
got="$(cd "$TMP/p" && ./app 2>&1 | tr -d '\r')"
want="control word same true
mxcsr same true
sqrt same true"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] thread_fp_env: a std.worker thread's floating-point state differs from main's"
    printf 'got:\n%s\nwant:\n%s\n' "$got" "$want" | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] thread_fp_env: a std.worker thread has main's x87 control word and MXCSR, and libm sqrt agrees bit for bit"
