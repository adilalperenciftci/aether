#!/bin/bash
# Test that generated C compiles without GCC extensions: the C a program gets
# when the C compiler is not GCC-compatible (AETHER_GCC_COMPAT 0), which is
# what MSVC compiles. Reached otherwise only by a few wasm programs, so a
# regression there (the closure constructor's qualifier warning of #2691) went
# unseen while nothing ran this script (#2725). `make test-msvc-compat` runs
# it, and the Windows workflow's MSVC job runs it with cl.exe.
#
#   AETHERC=<path>           the compiler that writes the C (default
#                            build/aetherc, run from the repository root)
#   MSVC_COMPAT_CC=gcc|cl|all
#                            which C compiler checks it. gcc: strict C11
#                            (-std=c11 -pedantic), AETHER_GCC_COMPAT forced to
#                            0, so the MSVC paths are compiled anywhere. cl:
#                            the real thing, where cl.exe is on PATH. Default:
#                            gcc, and cl as well when cl.exe is found.
#
# Under cl a program has to compile, and the warnings that mean a C type error
# (C4013 an undeclared function, C4024 and C4133 an argument of the wrong type,
# C4047 the wrong level of indirection, C4090 a dropped qualifier) are errors;
# the rest of /W3 is printed and allowed.
#
# The programs of tests 5-12 are tests/regression/test_issue<n>_*.ae, which
# the .ae sweep runs on the GCC path. Under gcc they are also built and run
# with AETHER_GCC_COMPAT forced to 0, when build/ae is there, so the plain C
# forms are checked for what they compute, not only that they compile.
set -e

cd "$(dirname "$0")/../.."

AETHERC="${AETHERC:-./build/aetherc}"
[ -f "$AETHERC" ] || [ ! -f "$AETHERC.exe" ] || AETHERC="$AETHERC.exe"
if [ ! -f "$AETHERC" ]; then
    echo "  [FAIL] $AETHERC not found: build the compiler first (make compiler)"
    exit 1
fi

case "${MSVC_COMPAT_CC:-}" in
    gcc) use_gcc=1; use_cl= ;;
    cl)  use_gcc=; use_cl=1 ;;
    all) use_gcc=1; use_cl=1 ;;
    "")  use_gcc=1; use_cl=; command -v cl >/dev/null 2>&1 && use_cl=1 ;;
    *)   echo "  [FAIL] MSVC_COMPAT_CC must be gcc, cl or all"; exit 1 ;;
esac
if [ -n "$use_cl" ] && ! command -v cl >/dev/null 2>&1; then
    echo "  [FAIL] MSVC_COMPAT_CC asks for cl, and cl.exe is not on PATH"
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== MSVC Compat Test: Verifying generated C compiles without GCC extensions ==="

# The C of one program, with AETHER_GCC_COMPAT forced to 0 at the very top,
# before any #ifndef guard can detect the compiler.
generate() {
    "$AETHERC" "$TMP/$1.ae" "$TMP/$1.c"
    { echo "#define AETHER_GCC_COMPAT 0"; cat "$TMP/$1.c"; } > "$TMP/$1_nogcc.c"
}

INC="-I. -Iruntime -Iruntime/utils -Iruntime/actors -Iruntime/config -Iruntime/scheduler -Iruntime/memory -Istd -Istd/collections -Istd/string"
# On glibc and musl, -std=c11 hides POSIX as well as the GNU extensions this
# checks for, so the POSIX branch of the generated C (clock_gettime and
# CLOCK_MONOTONIC behind clock_ns()) was undeclared on Linux. Strict C11 code
# that uses POSIX asks for it, as here; cl compiles the _WIN32 branches.
STRICT_POSIX=""
case "$(uname -s 2>/dev/null)" in
    Linux*) STRICT_POSIX="-D_POSIX_C_SOURCE=200809L" ;;
esac

# cl <name>: compile <name>.c (no forcing needed: cl is not GCC-compatible).
# /experimental:c11atomics is what makes MSVC's <stdatomic.h> usable in C.
# Options are written with '-' and paths in Windows form, so neither MSYS2's
# nor Git Bash's argument conversion rewrites them.
cl_compile() {
    src=$(cygpath -m "$TMP/$1.c")
    obj=$(cygpath -m "$TMP/$1.obj")
    # shellcheck disable=SC2086
    if ! MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 cl -nologo -std:c11 \
            -experimental:c11atomics -Zc:preprocessor -W3 \
            -we4013 -we4024 -we4047 -we4090 -we4133 \
            $INC -c "$src" -Fo"$obj" >"$TMP/cl.log" 2>&1; then
        sed 's/^/    /' "$TMP/cl.log" | head -30
        echo "  [FAIL] $2 does not compile under cl.exe"
        exit 1
    fi
    grep -i "warning" "$TMP/cl.log" | sed 's/^/    (allowed) /' | head -10 || :
    echo "  [PASS] $2 compiles under cl.exe"
}

# Test 1: Non-actor program with string interpolation
cat > "$TMP/interp.ae" <<'AEOF'
get_msg(n) -> {
    msg = "count=${n}"
    msg
}

main() {
    r = get_msg(5)
    println(r)
}
AEOF
generate interp
if [ -n "$use_gcc" ]; then
    # shellcheck disable=SC2086
    gcc -c -o /dev/null "$TMP/interp_nogcc.c" $INC \
        $STRICT_POSIX -std=c11 -pedantic -Wno-unused-label -Werror 2>&1
    echo "  [PASS] Non-actor string interpolation compiles under C11 -pedantic"
fi
[ -z "$use_cl" ] || cl_compile interp "Non-actor string interpolation"

# Test 2: Actor program with computed goto fallback
cat > "$TMP/actor.ae" <<'AEOF'
message Ping { value: int }

actor Pinger {
    state count = 0

    receive {
        Ping(value) -> {
            count = count + value
        }
    }
}

main() {
    p = spawn(Pinger())
    p ! Ping { value: 1 }
    println("ok")
}
AEOF
generate actor

# Check that the switch-case fallback exists alongside computed goto
if grep -q 'goto \*dispatch_table' "$TMP/actor.c"; then
    if ! grep -q 'switch.*_msg_id' "$TMP/actor.c"; then
        echo "  [FAIL] Actor dispatch: missing switch fallback"
        exit 1
    fi
fi
echo "  [PASS] Actor dispatch has switch-case fallback"

if [ -n "$use_gcc" ]; then
    # Syntax-check only: it cannot link without the full runtime.
    # shellcheck disable=SC2086
    gcc -fsyntax-only "$TMP/actor_nogcc.c" $INC $STRICT_POSIX -std=c11 -Wno-unused-label 2>&1
    echo "  [PASS] Actor program syntax-checks under C11"
fi
[ -z "$use_cl" ] || cl_compile actor "Actor program"

# Test 3: a closure over arrays a `try` body writes (#2691). On this path the
# closure constructor takes its captures as parameters, and an array written
# in a `try` body has volatile elements (#2618): a parameter without the
# qualifier dropped it, which MSVC reports as C4090. The same over a string
# array is test 4.
cat > "$TMP/closure.ae" <<'AEOF'
capture(k: int) -> fn {
    nums = [1, 2]
    other = [3, 4]
    try {
        nums = other
        nums[0] = k
        panic("stop")
    } catch e {
        println(e)
    }
    int[2] copy = nums
    f = || {
        return nums[0] + nums[1] + copy[0]
    }
    return f
}

main() {
    g = capture(5)
    int n = call(g)
    println("${n}")
}
AEOF
generate closure
if [ -n "$use_gcc" ]; then
    # shellcheck disable=SC2086
    gcc -fsyntax-only "$TMP/closure_nogcc.c" $INC $STRICT_POSIX -std=c11 -Wno-unused-label \
        -Werror=discarded-qualifiers -Werror=incompatible-pointer-types \
        -Werror=implicit-function-declaration 2>&1
    echo "  [PASS] A closure over try-written arrays syntax-checks under C11"
fi
[ -z "$use_cl" ] || cl_compile closure "A closure over try-written arrays"

# strict_c11 <name> <what>: <name>_nogcc.c is C11 with no GNU extension in
# it. A statement expression `({ ... })` is named by gcc under -pedantic; an
# __auto_type is not, so the generated C is searched for one outside the
# preprocessor lines that spell the GCC path (the _AE_SEQ_* macros). The
# warnings -pedantic gives the runtime headers are not this test's.
strict_c11() {
    # shellcheck disable=SC2086
    if ! gcc -fsyntax-only "$TMP/$1_nogcc.c" $INC $STRICT_POSIX -std=c11 -pedantic \
            -Wno-unused-label -Werror=implicit-function-declaration \
            -Werror=incompatible-pointer-types >"$TMP/$1.log" 2>&1; then
        sed 's/^/    /' "$TMP/$1.log" | grep -v "^    In file included" | head -30
        echo "  [FAIL] $2 does not compile as C11"
        exit 1
    fi
    if grep -q "braced-groups" "$TMP/$1.log"; then
        grep -B2 -A3 "braced-groups" "$TMP/$1.log" | sed 's/^/    /' | head -30
        echo "  [FAIL] $2 has a GNU statement expression on the non-GCC path"
        exit 1
    fi
    if grep -n "__auto_type" "$TMP/$1.c" | grep -v "^[0-9]*:#" | head -5 | sed 's/^/    /' | grep .; then
        echo "  [FAIL] $2 has __auto_type on the non-GCC path"
        exit 1
    fi
    echo "  [PASS] $2 compiles as strict C11"
}

# Test 4 (#2765): the program of the issue. A string stored into an element
# of an array a `try` body writes, read through a closure: the element store
# takes the string through a temporary, a GNU statement expression on this
# path until then, which cl.exe rejects (C2059 at the `{`).
cat > "$TMP/closure_str.ae" <<'AEOF'
import std.string

capture(w: string) -> fn {
    names = ["lit", "lit"]
    try {
        names[0] = string.concat(w, "a")
        panic("stop")
    } catch e {
        println(e)
    }
    f = || {
        return string.length(names[0])
    }
    return f
}

main() {
    g = capture("w")
    int n = call(g)
    println("${n}")
}
AEOF
generate closure_str
[ -z "$use_gcc" ] || strict_c11 closure_str "A string stored into a try-written array element"
[ -z "$use_cl" ] || cl_compile closure_str "A string stored into a try-written array element"

# Tests 5-12: every construct that needs a temporary in the middle of an
# expression, one program per family, each of which the .ae sweep runs on the
# GCC path and checks. All of them were GNU statement expressions here
# (#2765), and left_to_right read operands out of order (#2813).
#   string_slots      a string taken into an owning slot: an element of a
#                     string array, a binding through a call that hands its
#                     argument back, a returned `if` view, a `string?` or a
#                     tuple of them returned, a container store, a release
#                     of a local, a field and an element
#   call_temps        an argument freed after its call (a value call, a void
#                     call, a closure literal, a call that may hand it back,
#                     an unannotated callee), a tuple view of a temporary, an
#                     interpolation value, a compared heap operand, `string?`
#                     comparisons, a sequence literal, a closure stored in a
#                     list, heap.free of an @observable box
#   operand_order     operands evaluated ahead in source order (#2478), in a
#                     call, an operation, a struct literal, an array literal
#                     and a message sent, operands narrower than int among
#                     them (their temporary has the type C promotes them to)
#   optionals         `f() or v`, `o!`, `o ?? d`, `o?.f`, `t!` and bit_set
#                     subsets
#   struct_values     a struct moved out of a local (also one a `try` writes),
#                     struct literals that take their fields, array fields
#                     filled from arrays, a condition's struct temporary
#   statement_values  an `or` with a block, a propagating `!` and a call with
#                     a trailing block, run ahead of their statement
#   helper_names      the struct helpers the forms above call, beside functions
#                     of the program named as those helpers once were
#   left_to_right     operands a later call writes, narrow globals and fields
#                     reached through pointers among them, read before it in
#                     interpolations, arguments, literals and operations (#2813)
PROGS="2765_string_slots 2765_call_temps 2765_operand_order 2765_optionals 2765_struct_values
    2765_statement_values 2765_helper_names 2813_left_to_right"
for issue_prog in $PROGS; do
    prog="${issue_prog#*_}"
    cp "tests/regression/test_issue$issue_prog.ae" "$TMP/$prog.ae"
    generate "$prog"
    [ -z "$use_gcc" ] || strict_c11 "$prog" "Temporaries: $prog"
    [ -z "$use_cl" ] || cl_compile "$prog" "Temporaries: $prog"
done

# The same programs built and run on this path, AETHER_GCC_COMPAT forced to 0
# by the C compiler's command line, so what the comma expressions compute is
# checked as well as that they compile. Needs `ae` (make ae stdlib) and gcc.
AE="./build/ae"
[ -f "$AE" ] || [ ! -f "$AE.exe" ] || AE="$AE.exe"
if [ -n "$use_gcc" ] && [ -f "$AE" ]; then
    for issue_prog in $PROGS; do
        prog="${issue_prog#*_}"
        if ! AE_CC="gcc -DAETHER_GCC_COMPAT=0" "$AE" run "tests/regression/test_issue$issue_prog.ae" \
                >"$TMP/$prog.run" 2>&1 || [ "$(tail -n 1 "$TMP/$prog.run" | tr -d '\r')" != "ok" ]; then
            sed 's/^/    /' "$TMP/$prog.run" | tail -20
            echo "  [FAIL] Temporaries: $prog does not run right without GCC extensions"
            exit 1
        fi
        echo "  [PASS] Temporaries: $prog runs right without GCC extensions"
    done
elif [ -n "$use_gcc" ]; then
    echo "  [SKIP] running the programs without GCC extensions: $AE not built"
fi

echo ""
echo "=== All MSVC compat tests passed ==="
