- **A string whose bytes look like a string header is read as bytes.** A
  `string` argument to a C function not declared `@aether` arrives as its
  characters, and some std and contrib C functions then asked those
  characters whether they were a counted string. A payload beginning with
  the header's magic bytes and plausible fields was taken for one, and a
  pointer made of payload bytes was followed: a crash, or a read of
  arbitrary memory, from a tar block, a regex subject, an HTTP response
  body, an SQLite blob or a bytes copy an attacker shapes. Every such
  parameter is now declared `@aether`, so C receives the counted string and
  never guesses (std.bytes `copy_from_string`, std.regex, std.tar,
  `http_response_set_body`, contrib.sqlite); docs/c-interop.md states the
  rule (#3297).
