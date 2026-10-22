# std.map

A string-keyed map of pointers.

Like `std.list`, it stores `ptr` and does not own the values. Rebinding a key
replaces its value without growing the map, and does not free the old one:
that is the caller's, because the map never claimed it.

A key is all of its bytes: two keys that differ only after an embedded NUL
are two keys, and `keys_get` returns each one whole.

`std.spec` keeps its whole framework state in one of these, which is a fair
demonstration of the intended use: a heterogeneous bag of handles keyed by
name.

```aether,run
import std.map
import std.collections

main() {
    m = map.new()
    value = collections.list_new()

    err = map.put(m, "key", value)
    println("put err='${err}' size=${map.size(m)}")

    println("bound:   ${map.has(m, "key")}")
    println("unbound: ${map.has(m, "absent")}")

    map.free(m)
    collections.list_free(value)
}
```
```output
put err='' size=1
bound:   1
unbound: 0
```

**`get` reports a missing key as success.** It guards `map == null` but not
membership, so `map.get(m, "absent")` returns `(null, "")`. Use `map_has` for
the unambiguous membership test, and null-check the pointer. `map.lookup(m,
k)` is the same answer without the error slot, the value or null, for a
caller that reads absence as null.

**A string value is read with `get_string`.** `get` hands back a `ptr`, and a
`ptr` given to a `string` local as it is (`name, _ = map.get(m, "k")` after
`name = ""`) would be read as text whatever it points at, and is refused:
E0202. `map.get_string(m, key)` says the value is a string and checks it is
one: `(value, "")`, `(null, "")` for a missing key, and `(null, "not a
string")` when the value is some other pointer (a list, a struct).

```aether,run
import std.map
import std.list

main() {
    m = map.new()
    inner = list.new()
    map.put(m, "name", "Ada")
    map.put(m, "items", inner)

    name, err = map.get_string(m, "name")
    println("name=${name} err='${err}'")
    _, err2 = map.get_string(m, "items")
    println("items: ${err2}")

    map.free(m)
    list.free(inner)
}
```
```output
name=Ada err=''
items: not a string
```

`map_keys` returns the key set for iteration, and must be released with
`map_keys_free`. Read it with `keys_size` and `keys_get`.

The returned strings are **borrowed** from the live map: valid until
`keys_free`, and only while the map still holds that entry. The snapshot does
not track later mutation, so a key removed from the map leaves a dangling
entry in a snapshot taken before the removal. Retain or copy anything that has
to outlive either.

Iteration order is bucket order and is **unspecified**. Sort the keys
(`std.sort.strings`) when the output has to be deterministic.

An out-of-range or negative index returns `""` rather than trapping. An empty
string is also a legitimate key, so check `keys_size` first if the difference
matters.

## Exports

`map_new`, `put`, `map_put_raw`, `map_put_string_owned`, `get`, `get_string`,
`map_get_raw`, `map_has`, `map_remove`, `map_size`, `map_clear`, `keys`,
`map_keys_raw`, `map_keys_free`, `keys_size`, `keys_get`, `map_free`.
