#!/bin/sh
# A clause set's result is the join of every clause's (#3061). Two that no
# one type holds, an int and a string, are E0200 naming both, at the clause
# that brings the second; so is an inferred clause wider than a type another
# clause writes. Before, the set took its first clause's type and the C
# compiler, or a silent truncation, met the rest. What a joined set returns
# is tests/regression/test_issue3061_clause_set_result_join.ae.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] clause_set_result_join: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

cat > "$TMP/unjoinable.ae" <<'AE'
label(0, n: int) -> n
label(k, n: int) -> "many"

main() { println("${label(1, 2)}") }
AE
out=$(cd "$TMP" && "$AE" check unjoinable.ae 2>&1)
case "$out" in
    *"error[E0200]: the clauses of 'label' return int (line 1) and string, which no one type holds"*"unjoinable.ae:2:"*) ;;
    *) echo "  [FAIL] unjoinable: not refused naming int and string at line 2"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

cat > "$TMP/wider_than_written.ae" <<'AE'
size(0, b: long) -> int {
    return 0
}
size(k, b: long) -> b

main() { println("${size(1, 5000000000)}") }
AE
out=$(cd "$TMP" && "$AE" check wider_than_written.ae 2>&1)
case "$out" in
    *"error[E0200]: the clauses of 'size' are written to return int (line 1), and this clause returns long, which that does not hold"*"wider_than_written.ae:4:"*) ;;
    *) echo "  [FAIL] wider_than_written: not refused naming int and long at line 4"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

# #3063: a clause that returns only `none` joins the others as `T?`; a set
# of only such clauses says no `T`, and one beside a written `T` that is no
# optional does not fit it. Both name what is missing.
cat > "$TMP/all_none.ae" <<'AE'
nothing(0) -> none
nothing(k) -> none

main() { println("${nothing(1) == none}") }
AE
out=$(cd "$TMP" && "$AE" check all_none.ae 2>&1)
case "$out" in
    *"error[E0200]: every clause of 'nothing' that returns a value returns \`none\`, an optional of no type: the set's result \`T?\` needs its \`T\`"*"all_none.ae:1:"*) ;;
    *) echo "  [FAIL] all_none: not refused naming the missing T at line 1"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

cat > "$TMP/none_beside_written.ae" <<'AE'
size(0, n: int) -> int {
    return n
}
size(k, n: int) -> none

main() { println("${size(1, 2)}") }
AE
out=$(cd "$TMP" && "$AE" check none_beside_written.ae 2>&1)
case "$out" in
    *"error[E0200]: the clauses of 'size' are written to return int (line 1), and this clause returns \`none\`, which that does not hold"*"none_beside_written.ae:4:"*"write the result type as an optional, \`-> int?\`"*) ;;
    *) echo "  [FAIL] none_beside_written: not refused naming int and \`-> int?\` at line 4"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] clause_set_result_join: clause results no one type holds are refused, naming both, and a set of only \`none\` names its missing T"
