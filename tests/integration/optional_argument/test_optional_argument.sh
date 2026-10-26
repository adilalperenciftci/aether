#!/bin/sh
# An optional is never unwrapped implicitly, and an argument is no exception
# (#3153). `shout(maybe(1))`, a `string?` given to a `string` parameter,
# passed the checker and failed in C ("incompatible type for argument 1 ...
# ae_opt_string"), alone or through a local; a local bound to a `string?` in
# one loop body and to a `string` in another did too, in either order (one
# variable for the function, so the `string` binding read back optional).
# Now each is E0200 at the argument with the way out, and a local bound to a
# `T` and a `T?` in sibling bodies is one `T?` in C as well, so the program
# that unwraps it runs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || AE="$ROOT/build/ae.exe"
[ -x "$AE" ] || { echo "  [SKIP] optional_argument: ae not built"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

prelude() {
    cat <<'AE'
maybe(n: int) -> string? {
    if n > 0 {
        return "n${n}"
    }
    return none
}

shout(s: string) -> string {
    return "${s}!"
}

AE
}

expect_error() {  # file, fixed string, label
    out="$(AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1)"
    if ! printf '%s' "$out" | grep -qF "$2"; then
        echo "  [FAIL] optional_argument: $3"
        printf '%s\n' "$out" | grep -E "^error|help:" | head -4 | sed 's/^/        /'
        fail=1
    fi
}

expect_run() {  # file, expected stdout, label
    out="$(AETHER_HOME="$ROOT" "$AE" run "$1" 2>&1 | tr -d '\r')"
    if [ "$out" != "$2" ]; then
        echo "  [FAIL] optional_argument: $3"
        printf '%s\n' "$out" | head -6 | sed 's/^/        /'
        fail=1
    fi
}

# The call itself.
{ prelude; cat <<'AE'
main() {
    println(shout(maybe(1)))
}
AE
} > "$tmp/direct.ae"
expect_error "$tmp/direct.ae" "Argument 1 's' of 'shout': expected string, got string?" \
    "a string? argument for a string parameter was not refused"
expect_error "$tmp/direct.ae" "give it one with \`v ?? fallback\`" \
    "the diagnostic does not name the way out"

# Through a local, re-bound in one block: the local keeps its first type.
{ prelude; cat <<'AE'
main() {
    c = maybe(0)
    c = maybe(1) ?? "empty"
    println(shout(c))
}
AE
} > "$tmp/rebind.ae"
expect_error "$tmp/rebind.ae" "expected string, got string?" \
    "an optional local re-bound to its payload was passed as the payload"

# The issue's shape: the string? loop first, the string loop second.
{ prelude; cat <<'AE'
main() {
    i = 0
    while i < 2 {
        c = maybe(i)
        if c == none {
            println("none")
        }
        i = i + 1
    }
    j = 0
    while j < 2 {
        c = maybe(j) ?? "empty"
        println(shout(c))
        j = j + 1
    }
}
AE
} > "$tmp/loops.ae"
expect_error "$tmp/loops.ae" "'c' is one variable for the whole function" \
    "a sibling loop's string? local passed as a string did not say why it is optional"

# The other order: the string loop first. Its C variable was a const char*.
{ prelude; cat <<'AE'
main() {
    j = 0
    while j < 2 {
        c = maybe(j) ?? "empty"
        println(shout(c))
        j = j + 1
    }
    i = 0
    while i < 2 {
        c = maybe(i)
        i = i + 1
    }
}
AE
} > "$tmp/loops_rev.ae"
expect_error "$tmp/loops_rev.ae" "'c' is one variable for the whole function" \
    "a string local beside a sibling loop's string? was passed as a string"

# Both orders compile and run once the reads unwrap the one string? local.
{ prelude; cat <<'AE'
main() {
    j = 0
    while j < 2 {
        c = maybe(j) ?? "empty"
        println(shout(c ?? "?"))
        j = j + 1
    }
    i = 0
    while i < 2 {
        c = maybe(i)
        println(c ?? "none")
        i = i + 1
    }
}
AE
} > "$tmp/loops_ok.ae"
expect_run "$tmp/loops_ok.ae" "$(printf 'empty!\nn1!\nnone\nn1')" \
    "a local bound to a string and a string? in sibling loops did not run"

# The ways out run: ??, !, and a match.
{ prelude; cat <<'AE'
main() {
    println(shout(maybe(0) ?? "fallback"))
    println(shout(maybe(2)!))
    v = maybe(3)
    println(match v {
        some(s) -> shout(s)
        none -> "none"
    })
}
AE
} > "$tmp/ok.ae"
expect_run "$tmp/ok.ae" "$(printf 'fallback!\nn2!\nn3!')" "an unwrapped optional argument did not run"

# An optional parameter still takes one.
{ prelude; cat <<'AE'
show(s: string?) -> string {
    return s ?? "none"
}

main() {
    println(show(maybe(0)))
    println(show(maybe(4)))
    println(show("plain"))
}
AE
} > "$tmp/opt_param.ae"
expect_run "$tmp/opt_param.ae" "$(printf 'none\nn4\nplain')" "an optional parameter refused an optional"

[ "$fail" -eq 0 ] && echo "  [PASS] optional_argument"
exit "$fail"
