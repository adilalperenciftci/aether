- **A struct's C layout is its declared fields.** The hidden
  `_heap_<field>` int that followed each `string` field is gone: a string
  field always owns the string it holds. `reflect.field_heap_offset` is
  removed; a generic writer releases the string a field holds and stores
  one it took a reference to (#2921).
