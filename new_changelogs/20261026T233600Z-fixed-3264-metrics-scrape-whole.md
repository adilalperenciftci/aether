- **The /metrics scrape lists every series.** It was written into a fixed
  64 KB buffer and the series that did not fit, about fifty in, were left
  out of every scrape without a word. The buffer now grows with the series,
  and a scrape it cannot finish is answered 500 rather than cut short. It is
  written without holding the lock every request's metrics take, so a scrape
  does not stall the server's requests while it runs (#3264, #3280).
