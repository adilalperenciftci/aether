#!/bin/sh
# #2607: `@target("avx2") import m as alias`, one binary with both widths.
#
# A game ships one executable. Built for the lowest CPU, its f32x8 lanes are
# two four-lane halves everywhere; built with -mavx2, it faults on a CPU
# without AVX2. A module imported at @target("avx2") is a second copy of it
# compiled for AVX2 beside the build's own, and the program picks one at
# run time with lanes.cpu_has_avx2(), as Box3D's wide4.c / wide8.c and
# b3SetSIMDWidth do. This checks:
#
#   1. Both copies compute the same bits, a module (not only main) can hold
#      both and dispatch between them, and two files importing the same
#      module at the target share one copy. lanes.native8() is true in the
#      copy and false in the build's own, on the GCC/Clang path on x86.
#   2. On the AETHER_GCC_COMPAT=0 path the copy is plain code with no
#      target attribute: it still runs and agrees, and native8() is false.
#   3. On x86-64 the copy's code is ymm and the rest of the program has
#      none, so the AVX2 instructions stay behind the CPU check.
#   4. What cannot work is a compile error naming it: an f32x8 or a
#      pointer to a lane struct passed between the copies (their C types
#      differ), a closure in the copy (emitted outside its region), an
#      import without an alias, and an unknown target.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -f "$AE.exe" ] && AE="$AE.exe"
CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || CC_BIN=gcc

if [ ! -f "$AE" ]; then
    echo "  [SKIP] lane_target: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0
export AETHER_HOME="$ROOT"

mkdir -p "$tmp/ok"
cat > "$tmp/ok/wide.ae" <<'AE'
import std.lanes

exports (scaled_sum, native, calls)

// Each copy counts its own calls: a module variable is per copy.
var g_calls = 0

struct Vec3W {
    x: f32x8
    y: f32x8
    z: f32x8
}

dot_w(a: Vec3W, b: Vec3W) -> f32x8 { return a.x * b.x + a.y * b.y + a.z * b.z }

load_w(p: ptr, at: long) -> Vec3W {
    return Vec3W { x: lanes.load8(p, at), y: lanes.load8(p, at + 8), z: lanes.load8(p, at + 16) }
}

// The entry takes and gives scalars and pointers only.
scaled_sum(p: ptr, n: int) -> float {
    g_calls = g_calls + 1
    acc = lanes.splat8(0.0)
    i = 0
    while i < n {
        v = load_w(p, (i * 24) as long)
        acc = acc + lanes.sqrt8(dot_w(v, v))
        i = i + 1
    }
    return lanes.sum8(acc) as float
}

native() -> bool { return lanes.native8() }
calls() -> int { return g_calls }
AE
cat > "$tmp/ok/engine.ae" <<'AE'
import std.lanes
import wide
@target("avx2") import wide as wide8

exports (run)

// 8 runs the AVX2 copy where the CPU has it, anything else the build's.
run(p: ptr, n: int, width: int) -> float {
    if width == 8 && lanes.cpu_has_avx2() { return wide8.scaled_sum(p, n) }
    return wide.scaled_sum(p, n)
}
AE
cat > "$tmp/ok/main.ae" <<'AE'
import std.lanes
import wide
import engine
@target("avx2") import wide as w8
extern malloc(n: int) -> ptr
extern free(p: ptr)

main() {
    raw = malloc(4 * 96)
    buf = raw as f32[]
    i = 0
    while i < 96 { buf[i] = ((i * 7) % 13) as f32 * 0.37; i = i + 1 }
    a = wide.scaled_sum(raw, 4)
    println("plain ${a} native ${wide.native()}")
    if lanes.cpu_has_avx2() {
        b = w8.scaled_sum(raw, 4)
        println("copy same ${a == b} native ${w8.native()}")
    } else {
        println("copy not run: no AVX2")
    }
    println("engine same ${engine.run(raw, 4, 8) == engine.run(raw, 4, 4)}")
    println("calls ${wide.calls()} ${w8.calls()}")
    free(raw)
}
AE

# What the copy reports: AVX2 code on the GCC/Clang path on x86, plain code
# on the AETHER_GCC_COMPAT=0 path.
cat > "$tmp/probe.c" <<'C'
int main(void) {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_cpu_init(); return __builtin_cpu_supports("avx2") ? 0 : 1;
#else
    return 1;
#endif
}
C
has_avx2=0
if "$CC_BIN" -o "$tmp/probe" "$tmp/probe.c" 2>/dev/null && "$tmp/probe"; then has_avx2=1; fi

run_path() {   # <label> <want copy native> [AE_CC]
    label="$1"
    want_native="$2"
    rm -f "$tmp/ok/main" "$tmp/ok/main.exe"
    if [ -n "$3" ]; then
        (cd "$tmp/ok" && AE_CC="$3" "$AE" build main.ae -o "$tmp/ok/main" >"$tmp/ok/build.log" 2>&1)
    else
        (cd "$tmp/ok" && "$AE" build main.ae -o "$tmp/ok/main" >"$tmp/ok/build.log" 2>&1)
    fi
    if [ $? -ne 0 ]; then
        echo "  [FAIL] lane_target: the two-copy program did not build ($label):"
        grep -m8 -iE "error" "$tmp/ok/build.log" | sed 's/^/        /'
        fail=1
        return
    fi
    out="$("$tmp/ok/main" 2>&1 | tr -d '\r' | sed 's/^plain [0-9.]* /plain /')"
    if [ "$has_avx2" -eq 1 ]; then
        copy="copy same true native $want_native"
    else
        copy="copy not run: no AVX2"
    fi
    if [ "$has_avx2" -eq 1 ]; then calls="calls 2 2"; else calls="calls 3 0"; fi
    want="plain native false
$copy
engine same true
$calls"
    if [ "$out" != "$want" ]; then
        echo "  [FAIL] lane_target: wrong answers ($label)"
        printf 'got:\n%s\nwant:\n%s\n' "$out" "$want" | sed 's/^/        /'
        fail=1
    fi
}

x86=0
case "$(uname -m 2>/dev/null)" in x86_64|amd64|i686|i386) x86=1 ;; esac
# The ambient path is whatever $AE_CC (or the default) gives: when a sweep
# runs this file on the AETHER_GCC_COMPAT=0 path, its copy is plain too.
ambient=false
if [ "$x86" -eq 1 ]; then
    case "${AE_CC:-}" in *AETHER_GCC_COMPAT=0*) ;; *) ambient=true ;; esac
fi
run_path "the ambient C path" "$ambient"
run_path "AETHER_GCC_COMPAT=0" false "$CC_BIN -DAETHER_GCC_COMPAT=0"

# 3. Where the instructions are: ymm in the copy's functions, none elsewhere.
if [ "$x86" -eq 1 ] && command -v gcc >/dev/null 2>&1 &&
   (cd "$tmp/ok" && "$AETHERC" main.ae "$tmp/out.c" >/dev/null 2>&1); then
    if gcc -O2 -fwrapv -S -o "$tmp/out.s" $("$AE" cflags --cflags 2>/dev/null) "$tmp/out.c" 2>"$tmp/s.err"; then
        # Each ymm instruction is charged to the function whose label it
        # follows. A local label is not a function: `.L...` on ELF and COFF,
        # `L` + letters + a number (LBB0_1, Ltmp0, LCPI0_2) on Mach-O, whose
        # function labels carry a leading `_`. The copy's functions, and any
        # lane helper of its region left out of line, have `__avx2` in their
        # names.
        counts="$(awk '/^[A-Za-z_][A-Za-z0-9_.]*:/ && !/^L[A-Za-z_]*[0-9]/ { fn = $0 }
                       /ymm/ { if (fn ~ /__avx2/) copy++; else rest++ }
                       END { printf "%d %d", copy + 0, rest + 0 }' "$tmp/out.s")"
        copy_ymm=${counts% *}
        rest_ymm=${counts#* }
        if [ "$copy_ymm" -eq 0 ]; then
            echo "  [FAIL] lane_target: the @target copy has no ymm instruction (not compiled for AVX2)"
            fail=1
        fi
        if [ "$rest_ymm" -ne 0 ]; then
            echo "  [FAIL] lane_target: $rest_ymm ymm instructions outside the @target copy (AVX2 code not behind the CPU check)"
            fail=1
        fi
    else
        echo "  [FAIL] lane_target: the generated C did not compile:"
        head -5 "$tmp/s.err" | sed 's/^/        /'
        fail=1
    fi
    if gcc -O2 -fwrapv -S -DAETHER_GCC_COMPAT=0 -o "$tmp/out0.s" $("$AE" cflags --cflags 2>/dev/null) "$tmp/out.c" 2>"$tmp/s0.err"; then
        if grep -q ymm "$tmp/out0.s"; then
            echo "  [FAIL] lane_target: with AETHER_GCC_COMPAT=0 the @target region still carries a target attribute"
            fail=1
        fi
    else
        echo "  [FAIL] lane_target: the generated C did not compile with AETHER_GCC_COMPAT=0:"
        head -5 "$tmp/s0.err" | sed 's/^/        /'
        fail=1
    fi
fi

# 4. The compile errors.
expect_error() {   # <case> <message substring>
    if (cd "$tmp/$1" && "$AE" build main.ae -o "$tmp/$1/main" >"$tmp/$1/build.log" 2>&1); then
        echo "  [FAIL] lane_target: $1 built, want an error naming '$2'"
        fail=1
    elif ! grep -qF -- "$2" "$tmp/$1/build.log"; then
        echo "  [FAIL] lane_target: $1 failed without naming '$2':"
        grep -m5 -iE "error" "$tmp/$1/build.log" | sed 's/^/        /'
        fail=1
    fi
}

mkdir -p "$tmp/cross" "$tmp/crossptr" "$tmp/closure" "$tmp/alias" "$tmp/isa"
cat > "$tmp/cross/twice.ae" <<'AE'
import std.lanes
exports (twice)
twice(v: f32x8) -> f32x8 { return v + v }
AE
cat > "$tmp/cross/main.ae" <<'AE'
import std.lanes
@target("avx2") import twice as t8
main() { println("${lanes.sum8(t8.twice(lanes.splat8(1.0)))}") }
AE
expect_error cross "passes eight-lane values between a module imported at @target(\"avx2\") and the build's own code"

cp "$tmp/ok/wide.ae" "$tmp/crossptr/wide.ae"
cat >> "$tmp/crossptr/wide.ae" <<'AE'

zero(p: *Vec3W) {
    p.x = lanes.splat8(0.0)
    p.y = lanes.splat8(0.0)
    p.z = lanes.splat8(0.0)
}
AE
sed -i.bak 's/^exports (scaled_sum, native, calls)$/exports (scaled_sum, native, calls, zero, Vec3W)/' "$tmp/crossptr/wide.ae"
cat > "$tmp/crossptr/main.ae" <<'AE'
import std.lanes
import wide
@target("avx2") import wide as w8
main() {
    v = wide.Vec3W { x: lanes.splat8(1.0), y: lanes.splat8(2.0), z: lanes.splat8(3.0) }
    w8.zero(&v)
    println("${lanes.sum8(v.x)}")
}
AE
expect_error crossptr "passes eight-lane values between a module imported at @target(\"avx2\") and the build's own code"

cat > "$tmp/closure/bump.ae" <<'AE'
exports (run)
run() -> int {
    bump = |v: int| {
        v += 1
        println("bumped ${v}")
    }
    call(bump, 1)
    return 1
}
AE
cat > "$tmp/closure/main.ae" <<'AE'
@target("avx2") import bump as b8
main() { println("${b8.run()}") }
AE
expect_error closure "a closure inside a module imported at @target"

cp "$tmp/ok/wide.ae" "$tmp/alias/wide.ae"
cat > "$tmp/alias/main.ae" <<'AE'
@target("avx2") import wide
main() { println("x") }
AE
expect_error alias "@target(\"avx2\") import wide has no \`as\` name"

cp "$tmp/ok/wide.ae" "$tmp/isa/wide.ae"
cat > "$tmp/isa/main.ae" <<'AE'
@target("sse9") import wide as w
main() { println("x") }
AE
expect_error isa "@target expects the instruction set a module is compiled for again"

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] lane_target: @target(\"avx2\") import is a second copy, AVX2 behind the CPU check, same bits; crossings are errors"
fi
exit "$fail"
