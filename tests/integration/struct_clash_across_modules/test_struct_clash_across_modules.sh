#!/bin/sh
# Two modules defining one struct name (#2129), now that struct types are
# module-scoped.
#
# Struct names used to be one namespace across modules and the merge kept
# the first definition it saw, so a program importing two modules that each
# define `Quat` saw the LOSER's own code fail, until #2129 made it a
# diagnosed clash. Struct types are module-scoped now: each module's `Quat`
# is its own type (`geo.Quat`, `phys.Quat`, merged as `geo_Quat` and
# `phys_Quat`), so that program compiles and runs, as does one whose own
# `Quat` differs from an imported one. Two identical definitions still share
# one type. In an `--emit=lib` build a struct its module exports keeps its
# plain C name (the library's ABI), so there the clash is still reported,
# naming both field lists and both files.
#
# Message and actor names are still one namespace: a `message Ping {}`
# in one module and a `message Ping { x: int }` in another failed in the C
# compiler, attributed to the wrong module; two modules each defining
# `actor Worker` merged silently, and the loser's `spawn(Worker())` built
# the winner — its messages had no handler and went unanswered.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] struct_clash_across_modules: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

mkdir -p "$tmp/lib/geo" "$tmp/lib/phys" "$tmp/lib/same"
cat > "$tmp/lib/geo/module.ae" <<'AE'
exports(make_q, qx)
struct Quat { x: float, y: float, z: float, w: float }
make_q() -> Quat { return Quat { x: 1.0, y: 2.0, z: 3.0, w: 4.0 } }
qx(q: Quat) -> float { return q.x }
AE
cat > "$tmp/lib/phys/module.ae" <<'AE'
exports(make_p, ps, vx)
struct Vec3 { x: float, y: float, z: float }
struct Quat { v: Vec3, s: float }
make_p() -> Quat { return Quat { v: Vec3 { x: 1.0, y: 2.0, z: 3.0 }, s: 9.0 } }
ps(q: Quat) -> float { return q.s }
vx(v: Vec3) -> float { return v.x }
AE
cat > "$tmp/lib/same/module.ae" <<'AE'
exports(make_v)
struct Vec3 { x: float, y: float, z: float }
make_v() -> Vec3 { return Vec3 { x: 7.0, y: 8.0, z: 9.0 } }
AE

cat > "$tmp/clash.ae" <<'AE'
import geo
import phys
main() {
    a = geo.make_q()
    b = phys.make_p()
    println("${geo.qx(a)} ${phys.ps(b)}")
}
AE
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run clash.ae 2>&1)"
got="$(printf '%s\n' "$out" | tail -1)"
if [ "$got" != "1 9" ]; then
    echo "  [FAIL] struct_clash_across_modules: two modules' different 'Quat' structs did not build and run as two types (got '$got')"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
    fail=1
fi

# Importing both with neither used compiles too.
cat > "$tmp/unused.ae" <<'AE'
import geo
import phys
main() { println("x") }
AE
if ! (cd "$tmp" && AETHER_HOME="$ROOT" "$AETHERC" unused.ae out.c >/dev/null 2>&1); then
    echo "  [FAIL] struct_clash_across_modules: importing two modules with a same-named struct did not compile"
    fail=1
fi

# The program's own struct beside an imported one of the same name: the
# program's `Quat` is its own, geo's is geo.Quat.
cat > "$tmp/own.ae" <<'AE'
import geo
struct Quat { a: int }
main() {
    q = Quat { a: 1 }
    g = geo.make_q()
    println("${q.a} ${geo.qx(g)}")
}
AE
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run own.ae 2>&1)"
got="$(printf '%s\n' "$out" | tail -1)"
if [ "$got" != "1 1" ]; then
    echo "  [FAIL] struct_clash_across_modules: a program struct beside a same-named imported one did not run (got '$got')"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
    fail=1
fi

# --emit=lib keeps an exported struct's plain C name, so two exported
# structs of one name in one library are still the clash, reported with
# both field lists and files.
mkdir -p "$tmp/lib/xgeo" "$tmp/lib/xphys"
cat > "$tmp/lib/xgeo/module.ae" <<'AE'
exports(Quat, make_q)
struct Quat { x: float, y: float, z: float, w: float }
make_q() -> Quat { return Quat { x: 1.0, y: 2.0, z: 3.0, w: 4.0 } }
AE
cat > "$tmp/lib/xphys/module.ae" <<'AE'
exports(Quat, make_p)
struct Quat { s: float }
make_p() -> Quat { return Quat { s: 9.0 } }
AE
cat > "$tmp/libclash.ae" <<'AE'
import xgeo
import xphys
gx() -> float { q = xgeo.make_q(); return q.x }
ps() -> float { q = xphys.make_p(); return q.s }
AE
rm -f "$tmp/out.c"
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AETHERC" --emit=lib libclash.ae out.c 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] || [ -s "$tmp/out.c" ] ||
   ! printf '%s' "$out" | grep -q "struct 'Quat' is defined differently in two modules: {s: float} in lib/xphys/module.ae and {x: float, y: float, z: float, w: float} in lib/xgeo/module.ae. In an --emit=lib build a struct its module exports keeps its plain C name"; then
    echo "  [FAIL] struct_clash_across_modules: two exported same-named structs in an --emit=lib build were not reported"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
    fail=1
fi

# Identical definitions in two modules are one type, no diagnostic.
cat > "$tmp/same.ae" <<'AE'
import phys
import same
main() {
    v = same.make_v()
    println("${phys.vx(v)} ${phys.ps(phys.make_p())}")
}
AE
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run same.ae 2>&1)"
got="$(printf '%s\n' "$out" | tail -1)"
if [ "$got" != "7 9" ] || printf '%s' "$out" | grep -q "defined differently"; then
    echo "  [FAIL] struct_clash_across_modules: identical definitions no longer merge silently (got '$got')"
    printf '%s\n' "$out" | head -4 | sed 's/^/        /'
    fail=1
fi

# Messages and actors.
mkdir -p "$tmp/lib/ma" "$tmp/lib/mb" "$tmp/lib/mc"
cat > "$tmp/lib/ma/module.ae" <<'AE'
exports(start_a)
message Ping {}
actor Worker {
    state n = 0
    receive { Ping() -> { n = n + 1 } }
}
start_a() -> actor_ref { w = spawn(Worker()); w ! Ping {}; return w }
AE
cat > "$tmp/lib/mb/module.ae" <<'AE'
exports(start_b)
message Ping { x: int }
actor Runner {
    state total = 0
    receive { Ping(x) -> { total = total + x } }
}
start_b() -> actor_ref { w = spawn(Runner()); w ! Ping { x: 5 }; return w }
AE
cat > "$tmp/lib/mc/module.ae" <<'AE'
exports(start_c)
message Pong { x: int }
actor Worker {
    state total = 0
    receive { Pong(x) -> { total = total + x } }
}
start_c() -> actor_ref { w = spawn(Worker()); w ! Pong { x: 5 }; return w }
AE
cat > "$tmp/msg.ae" <<'AE'
import ma
import mb
main() { _ = ma.start_a(); _ = mb.start_b() }
AE
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AETHERC" msg.ae out.c 2>&1)"
if ! printf '%s' "$out" | grep -q "message 'Ping' is defined differently in two modules: {x: int} in lib/mb/module.ae and {} in lib/ma/module.ae"; then
    echo "  [FAIL] struct_clash_across_modules: a message defined differently in two modules was not reported"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
    fail=1
fi
cat > "$tmp/act.ae" <<'AE'
import ma
import mc
main() { _ = ma.start_a(); _ = mc.start_c() }
AE
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AETHERC" act.ae out.c 2>&1)"
if ! printf '%s' "$out" | grep -q "actor 'Worker' is defined in two modules: lib/mc/module.ae and lib/ma/module.ae"; then
    echo "  [FAIL] struct_clash_across_modules: an actor defined in two modules was not reported"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "  [PASS] struct_clash_across_modules: same-named structs of two modules are two types (a clash only between --emit=lib exports); identical ones share the type; messages and actors still clash"
fi
exit $fail
