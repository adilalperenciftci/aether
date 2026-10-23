- **`list.at(list, i)` and `map.lookup(map, key)`, and std and contrib use
  the containers' public functions.** `list.at` returns the item at an
  index the caller has bounded and panics, naming the index and the size,
  on one out of range, as a slice index does; `map.lookup` returns the
  value or null, `map.get` without its error slot. 25 files in std and
  contrib called std.list's and std.map's raw C bindings instead (286
  calls: `list_get_raw`, which read a null past the end, `list_add_raw`,
  `map_put_raw`, `map_get_raw`, `map_keys_*_raw`), and std.message read
  the map's key snapshot through a copy of its C struct layout. They call
  `list.at`, `list.add`, `map.put`, `map.lookup` and `map.keys` (#3107).
