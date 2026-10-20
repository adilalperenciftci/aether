#!/bin/sh
# #2550, #2603: moving values between lanes, and a lane's bits.
#
# A structure-of-arrays solver gathers eight records into one f32x8 per
# field: eight row loads and an 8x8 transpose in registers, as Box3D's
# b3TransposeW8 does (unpack, shuffle, permute2f128). Its separating axis
# test keeps a vertex index in the low mantissa bits of each candidate and
# finds both with one horizontal minimum. This checks:
#
#   1. Each move gives the lanes its comment says, an 8x8 and a 4x4
#      transpose built from them match a scalar transpose, the bit casts are
#      exact both ways (-0.0 included), the integer lanes add, and the
#      reductions pick the same lane for a tie and a NaN in the fixed order
#      the module documents.
#   2. On x86-64 with -mavx2, the 8x8 transpose is register shuffles on ymm
#      (vunpcklps, vshufps, vperm2f128 or vinsertf128), not eight scalar
#      inserts per field, which would pass every numeric check above and
#      lose the reason the moves exist.
#   3. Where the CPU has AVX2, the [build] cflags = "-mavx2" build prints the
#      same as the default (two-halves) build.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] lane_moves: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0
export AETHER_HOME="$ROOT"

cat > "$tmp/main.ae" <<'AE'
import std.lanes
extern malloc(n: int) -> ptr
extern free(p: ptr)

// Eight rows of eight floats at `src` into eight columns at `dst`.
transpose8(src: ptr, dst: ptr) {
    t0 = lanes.unpacklo8(lanes.load8(src, 0), lanes.load8(src, 8))
    t1 = lanes.unpackhi8(lanes.load8(src, 0), lanes.load8(src, 8))
    t2 = lanes.unpacklo8(lanes.load8(src, 16), lanes.load8(src, 24))
    t3 = lanes.unpackhi8(lanes.load8(src, 16), lanes.load8(src, 24))
    t4 = lanes.unpacklo8(lanes.load8(src, 32), lanes.load8(src, 40))
    t5 = lanes.unpackhi8(lanes.load8(src, 32), lanes.load8(src, 40))
    t6 = lanes.unpacklo8(lanes.load8(src, 48), lanes.load8(src, 56))
    t7 = lanes.unpackhi8(lanes.load8(src, 48), lanes.load8(src, 56))
    u0 = lanes.pairs_lo8(t0, t2)
    u1 = lanes.pairs_hi8(t0, t2)
    u2 = lanes.pairs_lo8(t1, t3)
    u3 = lanes.pairs_hi8(t1, t3)
    u4 = lanes.pairs_lo8(t4, t6)
    u5 = lanes.pairs_hi8(t4, t6)
    u6 = lanes.pairs_lo8(t5, t7)
    u7 = lanes.pairs_hi8(t5, t7)
    lanes.store8(dst, 0, lanes.halves_lo8(u0, u4))
    lanes.store8(dst, 8, lanes.halves_lo8(u1, u5))
    lanes.store8(dst, 16, lanes.halves_lo8(u2, u6))
    lanes.store8(dst, 24, lanes.halves_lo8(u3, u7))
    lanes.store8(dst, 32, lanes.halves_hi8(u0, u4))
    lanes.store8(dst, 40, lanes.halves_hi8(u1, u5))
    lanes.store8(dst, 48, lanes.halves_hi8(u2, u6))
    lanes.store8(dst, 56, lanes.halves_hi8(u3, u7))
}

transpose4(src: ptr, dst: ptr) {
    t0 = lanes.unpacklo4(lanes.load4(src, 0), lanes.load4(src, 4))
    t1 = lanes.unpackhi4(lanes.load4(src, 0), lanes.load4(src, 4))
    t2 = lanes.unpacklo4(lanes.load4(src, 8), lanes.load4(src, 12))
    t3 = lanes.unpackhi4(lanes.load4(src, 8), lanes.load4(src, 12))
    lanes.store4(dst, 0, lanes.pairs_lo4(t0, t2))
    lanes.store4(dst, 4, lanes.pairs_hi4(t0, t2))
    lanes.store4(dst, 8, lanes.pairs_lo4(t1, t3))
    lanes.store4(dst, 12, lanes.pairs_hi4(t1, t3))
}

lanes8(v: f32x8) -> string {
    return "${lanes.lane8(v, 0)} ${lanes.lane8(v, 1)} ${lanes.lane8(v, 2)} ${lanes.lane8(v, 3)} ${lanes.lane8(v, 4)} ${lanes.lane8(v, 5)} ${lanes.lane8(v, 6)} ${lanes.lane8(v, 7)}"
}

main() {
    src = malloc(256)
    dst = malloc(256)
    s = src as f32[]
    d = dst as f32[]
    i = 0
    while i < 64 { s[i] = (i * 3 + 1) as f32; i = i + 1 }
    transpose8(src, dst)
    wrong = 0
    r = 0
    while r < 8 {
        c = 0
        while c < 8 {
            if d[c * 8 + r] != s[r * 8 + c] { wrong = wrong + 1 }
            c = c + 1
        }
        r = r + 1
    }
    println("transpose8 wrong ${wrong}")
    transpose4(src, dst)
    wrong = 0
    r = 0
    while r < 4 {
        c = 0
        while c < 4 {
            if d[c * 4 + r] != s[r * 4 + c] { wrong = wrong + 1 }
            c = c + 1
        }
        r = r + 1
    }
    println("transpose4 wrong ${wrong}")

    a = lanes.f32x4(1.0, 2.0, 3.0, 4.0)
    b = lanes.f32x4(5.0, 6.0, 7.0, 8.0)
    x = lanes.unpacklo4(a, b)
    y = lanes.unpackhi4(a, b)
    p = lanes.pairs_lo4(a, b)
    q = lanes.pairs_hi4(a, b)
    println("four ${x.x} ${x.y} ${x.z} ${x.w} | ${y.x} ${y.y} ${y.z} ${y.w} | ${p.x} ${p.y} ${p.z} ${p.w} | ${q.x} ${q.y} ${q.z} ${q.w}")
    e = lanes.f32x8(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0)
    f = lanes.f32x8(9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0)
    println("unpack ${lanes8(lanes.unpacklo8(e, f))} | ${lanes8(lanes.unpackhi8(e, f))}")
    println("pairs ${lanes8(lanes.pairs_lo8(e, f))} | ${lanes8(lanes.pairs_hi8(e, f))}")
    println("halves ${lanes8(lanes.halves_lo8(e, f))} | ${lanes8(lanes.halves_hi8(e, f))}")

    bits = lanes.bits4(lanes.f32x4(1.0, -1.0, -0.0, 0.5))
    back = lanes.from_bits4(bits)
    println("bits4 ${lanes.mask_lane(bits, 0)} ${lanes.mask_lane(bits, 1)} ${lanes.mask_lane(bits, 2)} ${lanes.mask_lane(bits, 3)} back ${back.x} ${back.y} ${back.w}")
    b8 = lanes.bits8(lanes.f32x8(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, -0.0))
    println("bits8 ${lanes.mask8_lane(b8, 0)} ${lanes.mask8_lane(b8, 4)} ${lanes.mask8_lane(b8, 7)} back ${lanes.sum8(lanes.from_bits8(b8))}")
    idx = lanes.i32x8(0, 1, 2, 3, 4, 5, 6, 7) + lanes.i32splat8(16)
    println("i32x8 ${lanes.mask8_lane(idx, 0)} ${lanes.mask8_lane(idx, 7)} ${lanes.mask8_lane(idx * 2, 3)}")

    // Box3D's embedded index: the low seven mantissa bits carry the lane's
    // index, the minimum carries the winner's. Lanes 3 and 5 tie at 0.25;
    // the lower index wins.
    v = lanes.f32x8(3.0, 1.5, 9.0, 0.25, 7.0, 0.25, 2.0, 5.0)
    tagged = lanes.from_bits8(lanes.mask8_or(lanes.mask8_and(lanes.bits8(v), lanes.i32splat8(0 - 128)), idx))
    least = lanes.reduce_min8(tagged)
    println("embedded ${lanes.mask8_lane(lanes.bits8(lanes.splat8(least)), 0) % 128}")
    nan = lanes.lane8(lanes.sqrt8(lanes.splat8(-1.0)), 0)
    w = lanes.f32x8(nan, 2.0, 1.0, 4.0, 5.0, nan, 7.0, 8.0)
    w4 = lanes.f32x4(nan, 2.0, 1.0, 4.0)
    println("reduce ${lanes.reduce_min8(v)} ${lanes.reduce_max8(v)} ${lanes.reduce_min4(a)} ${lanes.reduce_max4(b)} nan ${lanes.reduce_min8(w)} ${lanes.reduce_max8(w)} ${lanes.reduce_min4(w4)} ${lanes.reduce_max4(w4)}")
    free(src)
    free(dst)
}
AE

expected="transpose8 wrong 0
transpose4 wrong 0
four 1 5 2 6 | 3 7 4 8 | 1 2 5 6 | 3 4 7 8
unpack 1 9 2 10 5 13 6 14 | 3 11 4 12 7 15 8 16
pairs 1 2 9 10 5 6 13 14 | 3 4 11 12 7 8 15 16
halves 1 2 3 4 9 10 11 12 | 5 6 7 8 13 14 15 16
bits4 1065353216 -1082130432 -2147483648 1056964608 back 1 -1 0.5
bits8 1065353216 1084227584 -2147483648 back 28
i32x8 16 23 38
embedded 19
reduce 0.25 9 1 8 nan 1 8 1 4"

if ! (cd "$tmp" && "$AE" build main.ae -o "$tmp/main" >"$tmp/build.log" 2>&1); then
    echo "  [FAIL] lane_moves: build failed:"
    grep -m5 -iE "error" "$tmp/build.log" | sed 's/^/        /'
    exit 1
fi
out="$("$tmp/main" 2>&1 | tr -d '\r')"
if [ "$out" != "$expected" ]; then
    echo "  [FAIL] lane_moves: wrong lanes"
    printf 'got:\n%s\nwant:\n%s\n' "$out" "$expected" | sed 's/^/        /'
    fail=1
fi

case "$(uname -m 2>/dev/null)" in
    x86_64|amd64)
        if "$AETHERC" "$tmp/main.ae" "$tmp/out.c" >/dev/null 2>&1 && command -v gcc >/dev/null 2>&1; then
            if gcc -O2 -mavx2 -fwrapv -S -o "$tmp/out.s" $("$AE" cflags --cflags 2>/dev/null) "$tmp/out.c" 2>"$tmp/s.err"; then
                body="$(awk '/^transpose8[.a-z0-9]*:/{p=1;next} p&&/^[A-Za-z_][A-Za-z0-9_.]*:/{p=0} p' "$tmp/out.s")"
                for want in vunpcklps vunpckhps vshufps; do
                    if ! printf '%s\n' "$body" | grep -q "$want.*ymm"; then
                        echo "  [FAIL] lane_moves: with -mavx2 the 8x8 transpose has no '$want' on ymm"
                        fail=1
                    fi
                done
                if ! printf '%s\n' "$body" | grep -qE "vperm2f128|vinsertf128"; then
                    echo "  [FAIL] lane_moves: with -mavx2 the 8x8 transpose does not pick halves with vperm2f128/vinsertf128"
                    fail=1
                fi
                if printf '%s\n' "$body" | grep -qE "insertps"; then
                    echo "  [FAIL] lane_moves: with -mavx2 the 8x8 transpose inserts lanes one at a time"
                    fail=1
                fi
            else
                echo "  [FAIL] lane_moves: the generated C did not compile with -mavx2:"
                head -5 "$tmp/s.err" | sed 's/^/        /'
                fail=1
            fi
        fi
        cat > "$tmp/probe.c" <<'C'
int main(void) { __builtin_cpu_init(); return __builtin_cpu_supports("avx2") ? 0 : 1; }
C
        if command -v gcc >/dev/null 2>&1 && gcc -o "$tmp/probe" "$tmp/probe.c" 2>/dev/null && "$tmp/probe"; then
            mkdir -p "$tmp/avx"
            cp "$tmp/main.ae" "$tmp/avx/main.ae"
            printf '[package]\nname = "lane_moves"\nversion = "0.1.0"\n\n[build]\ncflags = "-mavx2"\n' > "$tmp/avx/aether.toml"
            if (cd "$tmp/avx" && "$AE" build main.ae -o "$tmp/avx/main" >"$tmp/avx/build.log" 2>&1); then
                out_avx="$("$tmp/avx/main" 2>&1 | tr -d '\r')"
                if [ "$out_avx" != "$expected" ]; then
                    echo "  [FAIL] lane_moves: the -mavx2 build prints different lanes"
                    printf 'got:\n%s\n' "$out_avx" | sed 's/^/        /'
                    fail=1
                fi
            else
                echo "  [FAIL] lane_moves: the [build] cflags = \"-mavx2\" build failed:"
                grep -m5 -iE "error" "$tmp/avx/build.log" | sed 's/^/        /'
                fail=1
            fi
        fi
        ;;
esac

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] lane_moves: lane moves, transposes, bit casts, i32x8 and reductions exact in both forms; shuffles on ymm with -mavx2"
fi
exit "$fail"
