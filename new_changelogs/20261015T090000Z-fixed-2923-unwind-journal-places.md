- **A panic releases what each place holds, once.** The unwind journal now
  records places (a string local, a temporary, a struct local) by address
  where they are declared, and a panic releases what each holds at that
  moment. It used to record values: once two places could hold the same
  string, a release forgot the other place's entry, so a caught panic leaked
  a string or released one twice. The drain also no longer runs a release
  while it walks the journal (#2923).
