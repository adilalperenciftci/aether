- **A reverse proxy or load balancer answers 502 when its upstream cannot be reached.**
  The event-driven proxy path closed the client's connection with nothing
  written when the dial to the upstream was refused, the send failed or the
  upstream closed before answering, so the client saw "Empty reply from
  server" (curl exit 52) instead of the 502 the blocking path gives. The
  failure now goes to the proxy exchange as an errored response, which counts
  it against the upstream's breaker, retries where it may and otherwise makes
  the 502 or 504, with `X-Aether-Proxy-Error: upstream_transport`. Found by
  aeo's `spec_driver_loadbalancer_live`, which expects `aeo-lb` with a
  placeholder backend to answer.
