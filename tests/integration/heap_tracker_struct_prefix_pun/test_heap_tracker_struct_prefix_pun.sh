#!/bin/sh
# A wide struct written through a narrow prefix-view pointer keeps its fields
# intact (#1879-regression).
#
# #1879 appended hidden `_heap_<field>` trackers after a struct's declared
# fields. Two structs sharing a named prefix (the punning idiom: allocate the
# wide one, write it through the narrow prefix type) then disagreed on the
# tracker's offset, so a string write through the narrow view stamped a real
# data field of the wide object -- silent corruption. A struct now holds its
# declared fields and nothing else (#2921: every string field owns what it
# holds, with no flag), so the narrow struct is a memory prefix of the wide one.
#
# Two assertions: the program prints "ok" at runtime (a clobbered field prints
# CLOBBERED), and the C struct holds exactly the declared fields.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

if ! "$AETHERC" "$SCRIPT_DIR/prog.ae" "$TMP/out.c" > "$TMP/gen.log" 2>&1; then
    echo "  [FAIL] heap_tracker_struct_prefix_pun: codegen failed"
    sed 's/^/        /' "$TMP/gen.log" | head -8
    exit 1
fi

# CommonOptions holds its two declared members and nothing hidden.
common_body=$(awk '/typedef struct CommonOptions \{/{p=1} p{print} /} CommonOptions;/{if(p)exit}' "$TMP/out.c")
members=$(printf '%s\n' "$common_body" | grep -c ';')
if [ "$members" -ne 3 ] || ! printf '%s\n' "$common_body" | grep -q 'event_id;' ||
   ! printf '%s\n' "$common_body" | grep -q 'retry_ms;'; then
    echo "  [FAIL] heap_tracker_struct_prefix_pun: CommonOptions holds more than its declared fields"
    printf '%s\n' "$common_body" | sed 's/^/        /'
    exit 1
fi

# Compile and run: the field must survive the punned string write.
if ! "$AE" run "$SCRIPT_DIR/prog.ae" > "$TMP/run.log" 2>&1; then
    echo "  [FAIL] heap_tracker_struct_prefix_pun: program failed to run"
    sed 's/^/        /' "$TMP/run.log" | head -8
    exit 1
fi
if ! grep -q '^ok:' "$TMP/run.log"; then
    echo "  [FAIL] heap_tracker_struct_prefix_pun: field was clobbered"
    sed 's/^/        /' "$TMP/run.log" | head -4
    exit 1
fi

echo "  [PASS] heap_tracker_struct_prefix_pun: prefix-view string write leaves the wide field intact"
