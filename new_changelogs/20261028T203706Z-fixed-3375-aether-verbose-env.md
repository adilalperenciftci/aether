- **`AETHER_VERBOSE=1` prints the runtime configuration.** The variable was
  documented as printing the optimization configuration at startup, but it
  only set a flag nothing read: only a program compiled with
  `-DAETHER_VERBOSE` printed it. The runtime now prints it when the
  scheduler starts and the variable is set, whatever the program was
  compiled with; a program compiled with `-DAETHER_VERBOSE` (or a host
  passing `AETHER_OPT_VERBOSE`) still prints it, and it is printed once
  however many of them ask (#3375).
