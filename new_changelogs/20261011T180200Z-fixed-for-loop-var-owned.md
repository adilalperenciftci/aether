- **A C-style `for` loop's variable owns its value as the same binding in
  a `while` does.** A string loop variable leaked. The step
  (`for (s = "a"; ...; s = string.concat(s, "b"))`) was a raw C assignment
  in the header, or a raw store into the cell when a closure writes `s`, so
  each string it replaced was lost; and the init declared `s` in the header
  with no ownership flag, so the string the loop ended with was lost too,
  even with the step in the body. A struct that owns a string leaked the
  same way. The loop now declares its variable in a block of its own with
  the statement that binds it, and a step that binds a variable is that
  statement at the end of each pass, which a `continue` runs. A compound
  step (`i += 3`), a parse error before, is accepted (#2742).
