#!/bin/sh
# A signed integer beside a uint64 has no type that holds both (#3064): an
# if-expression's branches, a value match's arms and a clause set's results
# that are an int or a long and a uint64 are E0200 naming both. They took the
# first of the two before (a long beside a uint64), or the uint64 (an int
# beside one), and -1 came out 18446744073709551615. What the joins that
# exist compute is tests/regression/test_issue3064_signed_unsigned_join.ae.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] signed_unsigned_join: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <text> <line:col>: `ae check` refuses <name>.ae with an
# E0200 whose message holds <text>, at that position.
refused() {
    out=$(cd "$TMP" && "$AE" check "$1.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $1: accepted"
        fails=$((fails + 1))
        return
    fi
    case "$out" in
        *"error[E0200]"*"$2"*"$1.ae:$3"*) ;;
        *) echo "  [FAIL] $1: not E0200 \"$2\" at $3"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

cat > "$TMP/if_int_u64.ae" <<'AE'
main() {
    neg = -1
    uint64 u = 5
    v = if neg < 0 { neg } else { u }
    println("${v}")
}
AE
refused if_int_u64 "the branches of this if expression give values of types int and uint64" 4:9

cat > "$TMP/if_long_u64.ae" <<'AE'
main() {
    long neg = -1
    uint64 u = 5
    v = if neg < 0 { u } else { neg }
    println("${v}")
}
AE
refused if_long_u64 "give values of types uint64 and long" 4:9

cat > "$TMP/if_negative_literal_u64.ae" <<'AE'
main() {
    uint64 u = 5
    v = if u > 3 { -1 } else { u }
    println("${v}")
}
AE
refused if_negative_literal_u64 "give values of types int and uint64" 3:9

cat > "$TMP/match_int_u64.ae" <<'AE'
main() {
    k = 1
    neg = -1
    uint64 u = 5
    v = match k { 0 -> neg, _ -> u }
    println("${v}")
}
AE
refused match_int_u64 "the arms of this match give values of types int and uint64" 5:34

cat > "$TMP/clauses_int_u64.ae" <<'AE'
pick(0, s: int, u: uint64) -> s
pick(k, s: int, u: uint64) -> u

main() { println("${pick(1, -1, 5)}") }
AE
refused clauses_int_u64 "the clauses of 'pick' return int (line 1) and uint64" 2:1

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] signed_unsigned_join: a signed integer beside a uint64 is refused in a branch, an arm and a clause"
