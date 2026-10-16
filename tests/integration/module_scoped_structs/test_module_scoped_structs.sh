#!/bin/sh
# Struct types are module-scoped.
#
# Two modules each defining `struct Shader` was E0200 ("struct 'Shader' is
# defined differently in two modules"): a struct's C name was its plain
# name, so struct names were one namespace across modules, and ae3d had to
# call its own `GpuShader`, `GpuNode`, `ShaderImage` to stay clear of other
# modules' names. Now `gpu.Shader` and `core.Shader` are two types, merged
# and emitted as `gpu_Shader` and `core_Shader`; a program's own structs
# keep their names.
#
# A struct name resolves where it is written, as a function's does: the
# qualified `gpu.Shader` / `*gpu.Shader` / `gpu.Shader { ... }` names gpu's;
# a bare `Shader` is the file's own, else the one among its imports (a
# selective `import gpu (Shader)` picks between several), and two candidates
# are an error naming both qualified spellings. Identical definitions in two
# modules are still one type.
#
# Fixtures (lib/): gpu and core each define a different Shader; render names
# both; twin's Shader is gpu's field for field; shade's Light is named by a
# quote; dera and derb each @derive(eq) a struct Key; abi is built with
# --emit=lib.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] module_scoped_structs: ae not built"; exit 0; }
fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT

# expect_run FILE WANT: FILE builds and prints WANT (its lines joined by |)
expect_run() {
    out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run "$1" 2>&1 )
    got=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')
    if [ "$got" != "$2" ]; then
        echo "  [FAIL] module_scoped_structs: $1: expected '$2', got:"
        printf '%s\n' "$out" | head -12 | sed 's/^/          /'
        fail=1
    fi
}

# expect_error FILE AT MESSAGE: the build fails, at AT (file:line), with MESSAGE
expect_error() {
    out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" build "$1" -o "$tmp/out" 2>&1 )
    rc=$?
    if [ "$rc" -eq 0 ] || ! printf '%s\n' "$out" | grep -qF -- "$3" ||
       ! printf '%s\n' "$out" | grep -qF -- "--> $2:"; then
        echo "  [FAIL] module_scoped_structs: $1 should fail at $2 with: $3"
        printf '%s\n' "$out" | head -12 | sed 's/^/          /'
        fail=1
    fi
}

# Both Shaders in one program, qualified, as pointers and values, in
# literals and typed declarations, passed across modules; the program's own
# Shader beside them; twin's identical Shader is gpu's.
expect_run main.ae "gpu.Shader#7/frag|core.Shader:bloom/3|mine|core.Shader:fxaa/1 2|5 vert|gpu.Shader#9/vert + core.Shader:fxaa/1|7|gpu.Shader#4/twin"

# Each module's struct is its own C type; the program's keeps its name.
(cd "$SCRIPT_DIR" && AETHER_HOME="" "$AETHERC" main.ae "$tmp/main.c" >/dev/null 2>&1)
for t in gpu_Shader core_Shader gpu_Pass render_Binding Shader; do
    if ! grep -q "} $t;" "$tmp/main.c" 2>/dev/null; then
        echo "  [FAIL] module_scoped_structs: no struct '$t' in the generated C"
        fail=1
    fi
done
if grep -q "} twin_Shader;" "$tmp/main.c" 2>/dev/null; then
    echo "  [FAIL] module_scoped_structs: twin's Shader, identical to gpu's, was emitted as a type of its own"
    fail=1
fi

# A bare name: through the selective import that names it, or the only
# import that has it.
expect_run selective.ae "gpu.Shader#1/comp|core.Shader:m/2"
expect_run single.ae "core.Shader:solo/5"

# Errors: a bare name two imports define, in a type and in a literal; one
# module's Shader where the other's is expected; two same-named structs
# that both @derive (the derived function is named after the struct).
expect_error ambiguous.ae ambiguous.ae:5 \
    "struct 'Shader' is ambiguous here: the imported modules 'gpu' and 'core' each define one"
expect_error ambiguous.ae ambiguous.ae:5 "name the one you mean with its module: gpu.Shader or core.Shader"
expect_error ambiguous_literal.ae ambiguous_literal.ae:5 \
    "struct 'Shader' is ambiguous here: the imported modules 'gpu' and 'core' each define one"
expect_error mixed.ae mixed.ae:7 \
    "Argument 1 's' of 'core.weight_of': expected *core.Shader, got *gpu.Shader"
expect_error derive_clash.ae lib/derb/module.ae:3 \
    "@derive on two structs named 'Key' (dera.Key and derb.Key)"

# A quote names a module's struct as written: the same tree, and the same
# hash, as the program defining the struct itself.
mod_out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run quote_module.ae 2>&1 )
own_out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run quote_own.ae 2>&1 )
want_tree='(param x :float) (capture sun :Light) (BLOCK (LET l :Light (MAKE :Light (FIELD_VALUE power :float (LOCAL x :float)))) (RETURN :float (BINARY * :float (FIELD power :float (LOCAL l :Light)) (FIELD power :float (CAPTURE sun :Light)))))'
if [ "$(printf '%s\n' "$mod_out" | head -1)" != "$want_tree" ] || [ "$mod_out" != "$own_out" ]; then
    echo "  [FAIL] module_scoped_structs: a quote over a module's struct differs from one over the program's own"
    printf 'module:\n%s\nown:\n%s\n' "$mod_out" "$own_out" | sed 's/^/          /'
    fail=1
fi

# --emit=lib: an exported struct keeps its plain C name (the library's ABI);
# an unexported one is mangled.
if ! (cd "$SCRIPT_DIR" && AETHER_HOME="" "$AETHERC" --emit=lib libentry.ae "$tmp/lib.c" >/dev/null 2>&1); then
    echo "  [FAIL] module_scoped_structs: the --emit=lib build failed"
    fail=1
elif ! grep -q "} Vec2;" "$tmp/lib.c" || ! grep -q "} abi_Scratch;" "$tmp/lib.c"; then
    echo "  [FAIL] module_scoped_structs: --emit=lib should keep the exported Vec2 and mangle the unexported Scratch"
    grep -E "^\} [A-Za-z_]*;" "$tmp/lib.c" | head -5 | sed 's/^/          /'
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "  [PASS] module_scoped_structs: two modules' same-named structs are two types, named qualified or through imports; ambiguity is an error; quotes and --emit=lib exports keep their names"
exit 0
