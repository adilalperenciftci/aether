- **The runtime-copy tests check their claims on every platform.** Three
  tests assumed, as Windows has it, that a loaded library has a runtime of
  its own and that a program's copy is never found: on ELF a program
  linked with `-rdynamic` lends its runtime to a library, and on macOS an
  executable exports its globals. The failed-result importer now measures
  without holding the raised reason, and the foreign-layout cases of the
  accounts and the sandbox run their copies in libraries loaded after the
  foreign rendezvous, from hosts with no runtime of their own (#3437).
