- **The proxy event loop holds no more request bodies at once than the
  worker path would.** On Linux and macOS the loop reads each request's body
  whole before proxying it, up to the mount's cap per connection, and it
  reads every connection a client opens, so many connections each declaring
  a large body made it hold the cap times the number of connections. It now
  holds bodies over 16 KiB against a total of one cap per worker the worker
  path would run, and a request past that goes to the worker path, which
  streams it (#3263).
