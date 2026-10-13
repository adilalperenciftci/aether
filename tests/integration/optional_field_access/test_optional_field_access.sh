#!/bin/sh
# A field of an optional is read through `?.`, after `!`, or where a
# none-check narrows it; read plainly it is a type error (#2841 review).
#
# `o.r` on a `Shape?` (or `p.x` on a `Point?`) was accepted and reached C as
# a field of the `ae_opt_<T>` wrapper: gcc "'ae_opt_Shape' has no member
# named 'r'". So was `c3.r` after `c3 = o2`, a copy of a `Shape?` that #2841
# types as the optional. Each is now refused at the field, naming the ways
# in; those ways compile and run as before.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] optional_field_access: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

refused() {
    name="$1"; at="$2"; text="$3"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"error[E0200]"*"$text"*"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not E0200 \"$text\" at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

cat > "$TMP/sum_copy.ae" <<'AE'
struct Circle {
    r: float
}

struct Rect {
    w: float
    h: float
}

type Shape = Circle | Rect

main() {
    let o2: Shape? = none
    o2 = Circle { r: 2.0 }
    c3 = o2
    x = c3.r
    println("${x}")
}
AE
refused sum_copy 16:11 "Type 'Shape?' has no field 'r': it is an optional"

cat > "$TMP/struct_plain.ae" <<'AE'
struct Point {
    x: int
}

main() {
    let p: Point? = Point { x: 3 }
    println("${p.x}")
}
AE
refused struct_plain 7:17 "Type 'Point?' has no field 'x'"

cat > "$TMP/ways_in.ae" <<'AE'
struct Point {
    x: int
}

main() {
    let p: Point? = Point { x: 3 }
    a = p?.x ?? 0
    b = p!.x
    c = 0
    if p != none {
        c = p.x
    }
    println("ways ${a} ${b} ${c}")
}
AE
out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run ways_in.ae 2>&1)
case "$out" in
    *"ways 3 3 3"*) ;;
    *) echo "  [FAIL] ways_in: not \"ways 3 3 3\":"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

if [ "$fails" -ne 0 ]; then
    echo "  [FAIL] optional_field_access: $fails case(s)"
    exit 1
fi
echo "  [PASS] optional_field_access: a field of an optional is read through ?., ! or a narrowing"
