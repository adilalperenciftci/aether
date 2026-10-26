- **A module function keeps a C name no extern binds.** A function `name`
  of module `ns` is the C function `ns_name`, renamed only when the module
  had an extern of that Aether name. One bound through
  `@extern("ns_name")`, or another module's `extern ns_name(...)`, left
  one C function declared twice with two types, and the build stopped in
  the C compiler (#3187).
