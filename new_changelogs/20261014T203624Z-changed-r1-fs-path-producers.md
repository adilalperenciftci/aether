- **The path and filesystem string producers return counted strings.**
  `path.join`, `path.dirname`, `path.basename`, `path.extension`,
  `path.clean`, `path.rel` (and their std.fs spellings), `fs.readlink`,
  `fs.make_temp_dir`, `fs.make_temp_file` and the path slot of
  `fs.realpath` handed back a plain `malloc`'d buffer, which
  `string.release` cannot see and so leaves alone, and the std.path and
  std.fs externs for the path functions were not declared `@heap`, so
  only a list of names in the compiler kept them from leaking. Each now
  returns a refcounted string the caller owns and is declared `@heap`,
  as are the std.string, std.fs and std.file externs whose C already
  returned one (`string_concat`, `string_substring`, `string_replace`,
  `string_trim`, `file_read_all_raw` and the rest). `fs.realpath`
  without filesystem support returns an empty counted string where it
  returned a literal the caller would free. C code calling these
  functions reads the result with `aether_string_data` and releases it
  with `string_release`. This is part of stage 2 (R1) of the ownership
  model.
