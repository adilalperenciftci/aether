- **A retry on the proxy event loop no longer leaks its receive buffer.** On
  Linux and macOS a retry after an upstream's 5xx cleared the exchange with
  the connection's receive buffer still lent to it, dropping 16 KiB or more
  per retried attempt. The buffer is taken back before the next attempt
  starts (#3249).
