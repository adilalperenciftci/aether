- **A NUL byte in a request head is refused with 400.** The worker path
  looked for the end of a head with strstr, which stops at a NUL, and waited
  out the idle timeout for an end that had already arrived; on Linux and
  macOS the proxy event loop found the end, and the parse, stopping at the
  NUL, forwarded the rest of the head upstream as the request's body. Both
  paths now answer 400 malformed HTTP request (RFC 9110 section 5.5)
  (#3254).
