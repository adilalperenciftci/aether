#!/bin/sh
# Integration: single-value extern returning `string @heap` is honored by
# both the parser (annotation accepted at non-tuple return position) and
# the codegen heap-string classifier (`is_heap_string_expr` looks up the
# extern and reads the annotation). Without this:
#
#   - `extern http_request_body(req: ptr) -> string` returns a malloc'd
#     C buffer the caller is supposed to own, but the classifier sees
#     a bare extern call and marks `_heap_<lhs> = 0`. The reassignment
#     wrapper never frees the previous value, and the function-exit
#     defer-free never runs. Every call leaks the underlying buffer.
#
#   - There is no user-side workaround. The `string_concat(call(), "")`
#     refactor that worked for cross-Aether-fn classification does NOT
#     help here — string_concat copies its inputs but never frees them,
#     so wrapping just adds a second allocation alongside the leaked
#     first one.
#
# The fix:
#   1. Parser accepts `-> string @heap` at non-tuple return position
#      and stores the flag on the extern's AST node annotation slot.
#   2. `is_heap_string_expr` learns to look up `AST_EXTERN_FUNCTION`
#      decls by name and consult the annotation, mirroring the existing
#      `find_function_definition_by_name` user-fn path.
#
# What this test asserts (via `aetherc --diagnose=ownership`):
#   - `s = annotated_extern(...)` is moved: the call's result is fresh.
#   - `s = unannotated_extern(...)` is taken: the string stays C's, and the
#     local holds a reference of its own (R4: borrowed unless `@heap`).
#   - `s = wrapper_around_annotated_extern(...)` is moved too, and the
#     wrapper hands its caller one reference, as every string function
#     does (R3).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] extern_single_value_heap: aetherc not built"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/fixture.ae" <<'AE'
// Single-value extern annotated `@heap` — caller owns the returned
// buffer. Real-world shape: http_request_body, fs.read_to_string, …
extern owned_string(seed: string) -> string @heap

// Same shape but unannotated — the conservative default. Stays
// classified non-heap so existing externs (90%+ of which return
// borrowed pointers into module-owned storage) keep their pre-fix
// behaviour with no churn.
extern borrowed_string(seed: string) -> string

// A user wrapper around an annotated extern. The structural classifier
// already walks return statements; once `is_heap_string_expr`
// recognises the annotated extern at the return site, the wrapper
// inherits HEAP without an explicit annotation.
wrap_owned(seed: string) -> string {
    return owned_string(seed)
}

main() {
    s1 = owned_string("a")          // moved: fresh (annotated extern)
    s2 = borrowed_string("b")       // taken: borrowed (unannotated extern)
    s3 = wrap_owned("c")            // moved: fresh (through the wrapper)
}
AE

out="$tmpdir/diagnose.txt"
if ! "$AETHERC" --diagnose=ownership "$tmpdir/fixture.ae" >"$out" 2>&1; then
    echo "  [FAIL] extern_single_value_heap: aetherc --diagnose=ownership exited non-zero"
    cat "$out"
    exit 1
fi

# s1: an annotated extern's result is fresh, and moved into the local.
if ! grep -qE "^    line +[0-9]+: s1 +=.*  move +\[fresh" "$out"; then
    echo "  [FAIL] extern_single_value_heap: s1 = owned_string(...) should be moved (fresh)"
    cat "$out"
    exit 1
fi

# s2: an unannotated extern's result is C's, and taken (opt-in via
# annotation only).
if ! grep -qE "^    line +[0-9]+: s2 +=.*  take +\[borrowed" "$out"; then
    echo "  [FAIL] extern_single_value_heap: s2 = borrowed_string(...) should be taken (borrowed)"
    cat "$out"
    exit 1
fi

# s3: the wrapper's result is fresh as well.
if ! grep -qE "^    line +[0-9]+: s3 +=.*  move +\[fresh" "$out"; then
    echo "  [FAIL] extern_single_value_heap: s3 = wrap_owned(...) should be moved (fresh)"
    cat "$out"
    exit 1
fi

if ! grep -qE "^  wrap_owned .* hands its caller one reference from every return" "$out"; then
    echo "  [FAIL] extern_single_value_heap: wrap_owned should hand its caller a reference"
    cat "$out"
    exit 1
fi

# End-to-end runtime probe — builds a small program that drives 10k
# iterations of an annotated extern with libc-malloc'd returns, plus a
# mix of borrowed-returns to confirm the over-free regression case.
# The classifier verdicts above prove the wrapper IS emitted; this
# probe proves the emitted code runs without crashing — the freed
# memory is genuinely a libc-malloc'd buffer, not a static pointer or
# a literal.
AE="$ROOT/build/ae"
if [ ! -x "$AE" ]; then
    echo "  [SKIP] extern_single_value_heap: ae not built (probe step skipped)"
    exit 0
fi

probe_log="$tmpdir/probe_build.log"
cd "$SCRIPT_DIR" || exit 1
if ! "$AE" build probe.ae -o "$tmpdir/probe" >"$probe_log" 2>&1; then
    echo "  [FAIL] extern_single_value_heap: probe build failed"
    sed 's/^/    /' "$probe_log" | head -30
    exit 1
fi

probe_out="$tmpdir/probe.out"
if ! "$tmpdir/probe" > "$probe_out" 2>&1; then
    echo "  [FAIL] extern_single_value_heap: probe exited non-zero"
    sed 's/^/    /' "$probe_out" | head -20
    exit 1
fi
if ! grep -q "all probes passed" "$probe_out"; then
    echo "  [FAIL] extern_single_value_heap: probe output missing success marker"
    sed 's/^/    /' "$probe_out" | head -20
    exit 1
fi

echo "  [PASS] extern_single_value_heap: @heap annotation honored at parser + codegen, runtime probe (10k iter loop) clean"
exit 0
