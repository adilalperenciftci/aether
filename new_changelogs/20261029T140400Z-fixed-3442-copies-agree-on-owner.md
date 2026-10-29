- **Runtime copies agree on which one owns the sandbox levels and the
  accounts, whatever order they looked in.** The lookup of the first loaded
  image that exports the rendezvous took a definition through the program's
  handle, which searches every global library whenever it was loaded, or
  through a library's handle, which searches its dependencies, so two
  copies could pin different owners and not see each other's levels. A
  definition now counts only inside the image being visited, and the list
  of loaded objects grows past 512 (#3442).
