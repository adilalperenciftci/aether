- **The 16 KiB request head bound holds however the head is read.** The
  worker path bounded a head by its connection buffer, which grows for a
  buffered body, so after a request with a 16 KiB body the next head could be
  twice as long; the proxy event loop checked the bound only until it found
  the head's end, so a head that ended past 16 KiB within one read was
  accepted. Both now refuse any head over 16 KiB with 431 (#3253).
