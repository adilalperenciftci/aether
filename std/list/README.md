# std.list

A growable list of pointers.

The list stores `ptr` and does not own what they point at: freeing the list
frees its own storage, not the elements. That is what lets the same container
hold borrowed references, arena-allocated values, or handles from another
module without a lifetime argument.

Two kinds of element are the exception, and the list owns them: a heap
string and a closure value. The compiler routes `list.add` of either to an
owning add (`list_add_string_owned` takes its own reference to the string,
or a copy of a plain one; a closure's environment gets a reference of its
own, #2518), so the caller keeps and frees its own copy. The list gives back
what it owns when the element leaves it: `list_remove`, `list_clear`,
`list_free`, and a string or closure value stored over the slot with
`list.set` (the new string is owned the way `add` owns it: a fresh value
adopted, a local moved or copied, any other string copied). `list_set` of a
raw pointer leaves what the slot held to its caller (a sort or a swap puts
it back in another slot through the same call) and the new pointer stays
the caller's. A pointer read with `get` from an owned element is valid only
while the element is in the list.

`add` and `get` are the `(value, err)` wrappers; the `list_*` forms are the
direct ones.

```aether,run
import std.list
import std.collections
import std.mem

main() {
    l = list.new()

    // Any pointer will do; a second list makes a convenient one.
    item = collections.list_new()

    err = list.add(l, item)
    println("add err='${err}' size=${list.size(l)}")

    got, gerr = list.get(l, 0)
    println("same pointer back: ${mem.ptr_to_long(got) == mem.ptr_to_long(item)}")

    list.free(l)
    collections.list_free(item)
}
```
```output
add err='' size=1
same pointer back: true
```

**`get` checks the index.** `list.get(l, 99)` on a shorter list returns
`(null, "index out of range")`, and a null list returns `(null, "null list")`,
so an empty error always means the value is good. A loop that has already
bounded the index by `list_size` reads with `list.at(l, i)`, which returns
the item alone and panics, naming the index and the size, on an index out
of range, as a slice index does. `list_get_raw` is the C binding both are
built on, for std.list itself (#3107).

**A string element is read with `get_string`.** `get` hands back a `ptr`,
which a `string` local would read as text whatever it points at, so giving
it to one is refused (E0202). `list.get_string(l, i)` says the element is a
string and checks it is one: an element that is some other pointer (a nested
list, a struct) gives `(null, "not a string")`, with the index and null-list
errors `get` gives.

## Exports

`list_new`, `list_new_in`, `add`, `list_add_raw`, `list_add_string_owned`,
`get`, `get_string`, `list_get_raw`, `list_set`, `list_size`, `list_remove`, `list_clear`,
`list_free`.
