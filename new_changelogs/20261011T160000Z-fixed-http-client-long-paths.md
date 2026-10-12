- **`std.http.client` sends a request path of any length whole.** It copied
  the path into a fixed 1,024-byte buffer, cut a longer one at 1,023 bytes,
  and sent the request anyway, so the server answered for a path the caller
  never asked for (a 1,500-byte OpenAlex filter got a 400; a server that
  takes any path answered 200 for the wrong thing). The path is now sized
  from the URL, and so are the paths a relative redirect is resolved
  against and the ones the proxy driver forwards; a URL whose host does not
  fit is refused as malformed rather than cut. A redirect's origin check now
  strips `Authorization`, `Cookie` and `Proxy-Authorization` unless both
  URLs parse and their origins match (#2674).
