- **A TLS keep-alive connection that sends a KeyUpdate no longer holds a
  worker.** A KeyUpdate (or another record with no application data) on an
  idle keep-alive connection was taken as the next request: the pure TLS
  backend's pending check counted any whole buffered record, and on both
  backends a socket that turned readable sent the worker into a read that
  handled the record and then waited for the whole idle timeout (30 s by
  default). With every worker so held, other clients waited that long. Now
  a TLS connection whose socket turns readable is asked, without waiting,
  whether a read would find data: the pure backend handles the whole
  records the socket holds, and OpenSSL peeks with the socket non-blocking.
  One with none is parked, or parked again when the lot woke it, for what is
  left of its idle time. The pure server also reports its socket's receive
  timeout after the handshake as a timeout, keeping the connection, instead
  of retrying it for about 5 s and then failing the connection (#3405).
