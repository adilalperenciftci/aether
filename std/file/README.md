# std.file

Files by path, plus a handle for reading one you keep open: open, read_all,
close.

`std.file` is the short form of `std.fs`'s file calls. `write`, `read`,
`delete` and `size` take a path and do the whole job in one call. `open`
gives a handle when you need one: to read the file again from the start, or
to hand its descriptor (`fd`) to something else. For positional reads and
writes through a handle, use `std.fs` (`fs.pread`, `fs.pwrite`).

The example **compiles but is not run** in CI: it touches the filesystem.

```aether
import std.file

main() {
    werr = file.write("/tmp/notes.txt", "first line\n")
    if werr != "" {
        println("write failed: ${werr}")
        return
    }

    handle, err = file.open("/tmp/notes.txt", "r")
    if err != "" {
        println("open failed: ${err}")
        return
    }
    defer file.close(handle)

    text, rerr = file.read_all(handle)
    if rerr != "" {
        println("read failed: ${rerr}")
        return
    }
    print(text)

    println("exists: ${file.exists("/tmp/notes.txt")}")
    _ = file.delete("/tmp/notes.txt")
}
```

Every call returns `""` for success or the reason it failed, beside its
value where it has one. `write` also reports a write that only failed when
the file was closed, such as to a full disk: the data was in the handle's
buffer and never reached the disk.

`fd(handle)` exposes the underlying descriptor, which is what a caller passes
to `std.tcp`'s poll or to a C interface expecting an `int`. The handle owns
it: close the handle, never the descriptor.

Modes follow C's `fopen`: `"r"`, `"w"`, `"a"`, with `"b"` where binary matters
(no-op on POSIX, load-bearing on Windows).

A handle must be closed, with `file.close` (`defer file.close(h)` right after
a successful open). Nothing closes it for you at the end of the scope.

## Exports

`open`, `close`, `read_all`, `read`, `write`, `delete`, `size`, `fd`, `file_exists`.
