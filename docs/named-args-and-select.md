# Named Arguments and select()

## Named Arguments

Function calls can use named arguments with colon syntax, consistent
with Aether's parameter definition style:

```aether,fragment
// Definition
greet(name: string, count: int) {
    for (i = 0; i < count; i++) { println(name) }
}

// Call with named args
greet(name: "alice", count: 3)

// Positional still works
greet("alice", 3)

// Mixed: positional first, named after
greet("alice", count: 3)

// Any order: each goes to the parameter it names
greet(count: 3, name: "alice")
```

A named argument is passed to the parameter it names, wherever it is
written. A parameter with a default can be left out, and a named
argument can skip over it:

```aether,run
box(w: int, h: int = 1, d: int = 1) -> int {
    return w * 100 + h * 10 + d
}

main() {
    println(box(2, d: 4))
    println(box(d: 3, w: 5))
}
```

```output
214
513
```

The arguments are still evaluated in the order written, left to right:
`f(b: next(), a: next())` calls `next()` for `b` first.

### Rules

- Names use colon: `name: value` (not `name = value`)
- Positional arguments come first, then named ones; a positional
  argument after a named one is an error
- A name must be one of the function's parameters, and a parameter takes
  one argument: an unknown name, or a parameter given twice (by name, or
  by position and by name), is an error
- A parameter with no default that the call leaves out is an error
- A trailing closure or block after the parentheses is the last argument
- Only a function or an extern whose parameters have names takes named
  arguments; a closure or a function pointer called with one is an error
- The colon syntax is consistent with parameter definitions: `func(name: type)`

Each mistake is a compile error (E0200) at the call:

```aether,fails
box(w: int, h: int = 1, d: int = 1) -> int {
    return w * 100 + h * 10 + d
}

main() {
    println(box(2, w: 3))       // parameter 'w' of 'box' is given twice
    println(box(h: 2))          // the call of 'box' gives no argument for parameter 1 'w'
    println(box(w: 1, q: 2))    // 'box' has no parameter named 'q'
    println(box(w: 1, 5))       // a positional argument after a named one
}
```

## List Literals

Array literals with square bracket syntax:

```aether,fragment
nums = [10, 20, 30]
println(nums[0])         // 10

names = ["alice", "bob", "charlie"]
println(names[1])        // bob

// Expressions in array literals
a = 5
computed = [a, a * 2, a * 3]     // [5, 10, 15]

// Empty array
empty = []

// Single element
one = [42]
```

Arrays are fixed-size C arrays. Element access uses `[]` subscript.

## select(), Platform Conditional

Compile-time platform selection using named arguments:

```aether,fragment
port = select(linux: 8080, windows: 80, macos: 8080)
timeout = select(windows: 5000, other: 3000)
flags = select(linux: "-lpthread", windows: "-lws2_32", macos: "-framework Security")
```

### How it works

`select()` emits a C `#ifdef` chain at compile time. Only the matching
platform's value is compiled into the binary:

```c
// select(linux: 8080, windows: 80, macos: 8080) compiles to:
#ifdef _WIN32
80
#elif defined(__APPLE__)
8080
#else
8080
#endif
```

### Platform names

| Name | C condition | Matches |
|------|-----------|---------|
| `linux:` | `#else` (default) | Linux, FreeBSD, other POSIX |
| `windows:` | `#ifdef _WIN32` | Windows, MinGW, MSYS2 |
| `macos:` | `#elif defined(__APPLE__)` | macOS, iOS |
| `other:` | fallback | Any platform not explicitly listed |

### Fallback with `other:`

`other:` provides a default value for platforms not explicitly named:

```aether,fragment
// Only need to specify the exception
separator = select(windows: "\\", other: "/")
```

### Missing platform is a compile error

If a platform is missing and there is no `other:` fallback, the Aether
compiler refuses the program with E0701, whatever platform it builds for:
the generated C is the same for every platform, so a value missing for one
of them is missing for the program.

```aether,fails
main() {
    port = select(linux: 8080)
    println(port)
}
// error[E0701]: select() has no value for windows and macos and no `other:`
// fallback; its branches are `linux:`
// help: add `windows:` and `macos:`, or `other:` for every platform it does not name
```

This prevents silent bugs where a platform gets `0` or empty string.
Either list all platforms or provide `other:`. A key that is not a platform
is a build symbol: when the build defines it, its value is the select's and
the platforms are not consulted.

### Use cases

**Build system flags:**
```aether,fragment
linker_flags = select(
    linux: "-lpthread -lrt",
    windows: "-lws2_32",
    macos: "-framework Security"
)
```

**Default paths:**
```aether,fragment
config_dir = select(
    linux: "/etc/myapp",
    macos: "/Library/Application Support/myapp",
    windows: "C:\\ProgramData\\myapp"
)
```

**Feature availability:**
```aether,fragment
max_threads = select(linux: 16, windows: 8, macos: 12)
has_io_uring = select(linux: 1, other: 0)
```

### String results

A `select()` whose values are strings is a `string`, and binds, prints and
interpolates as one:

```aether,run
import std.string

main() {
    sep = select(windows: "\\", other: "/")
    os = select(linux: "Linux", windows: "Windows", macos: "macOS")
    println("${string.length(sep)} ${string.length(os) > 0}")
}
```

```output
1 true
```
