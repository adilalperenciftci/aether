- **Request metrics are bounded and found by hash.** The per-route counters
  were keyed by the method and path a client sent, one series per pair
  without limit, in a list every request walked under one lock: a client
  requesting fresh paths grew them, and slowed every request, for as long as
  it liked. Past 1024 series a request now counts in one series labelled
  `(other)`, the same series a request sending those labels itself counts
  in, so no two series share labels, and a series is found by hash (#3265,
  #3279).
