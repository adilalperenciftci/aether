- **A `std.tcp` write to a connection the peer closed fails instead of
  ending the process.** Its sends passed no flags, on sockets without
  `SO_NOSIGPIPE`, so the write raised SIGPIPE and the program ended with no
  output; on macOS the pure TLS client and server died that way when the
  other side closed first. Sends now name `MSG_NOSIGNAL` where the platform
  has it and sockets carry `SO_NOSIGPIPE` where it has that, as the HTTP
  server's always did, and the write fails with EPIPE (#3457).
