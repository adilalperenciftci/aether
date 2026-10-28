- **http_proxy_send_timeout tests the server, and std.tcp can size a
  receive buffer before connecting.** The test's worker-path case received
  every byte now and then, on two causes, both the test's:
  - Its client set its receive buffer after connecting, so the window the
    connection opened with still stood. On Linux it took that much through
    the stall, then drained it for sixteen seconds after the cut.
  - macOS's loopback, about two seconds into a client's stall, in some runs
    has the sender's kernel report tens of megabytes sent and acknowledged,
    while the client sends nothing and the bytes cross only once it reads
    (measured with TCP_CONNECTION_INFO and a capture of lo0). No sender can
    tell that from a client that reads, so the server rightly went on. The
    worker path's cut, at its first full buffer plus the one second timeout,
    met it at two seconds: 21 runs in 480.

  New `tcp.connect_buffered(host, port, read_buffer)` sets the buffer before
  the connection is made, and `tcp.available(sock)` says how many bytes wait
  in the receive buffer. The test connects with the first and uses a 300 ms
  idle timeout, so every cut comes before macOS's absorption: 80 runs of 80
  on macOS, 40 of 40 on Linux (#3338).
