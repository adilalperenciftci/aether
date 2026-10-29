- **An unloaded library's runtime copy is no longer written into by the
  execution accounts.** Every runtime copy registered its allocation
  fast-path word with the accounts it shares at its first call and never
  left: once a plugin library with a runtime of its own was unloaded,
  making the first account (or freeing the last) wrote into its unmapped
  image. A copy now leaves the accounts when it is unloaded. The list of
  copies also grows as needed, where a 65th copy was refused and then
  never told that an account was in use, so its allocations went
  uncharged; a copy that cannot join the list asks the accounts on every
  allocation instead (#3411).
