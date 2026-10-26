- **The proxy event loop answers a request it cannot parse.** On Linux and
  macOS a request that did not parse (`GARBAGE`, an HTTP version other than
  1.x) or whose Content-Length could not be read (two that disagree, one
  that is not a number) had its connection closed with nothing written. The
  loop now gives it to the worker path with the bytes it read, which answers
  400, as it does on Windows and on every server the loop does not serve
  (#3233).
