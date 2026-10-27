- **Every /metrics series has labels of its own, in UTF-8.** A series was
  keyed on the whole method and path a request carried, but written with
  them cut at 63 and 255 bytes, so two paths that agreed that far were two
  series with the same labels; and a path's bytes went into its label as
  sent, ones that are not UTF-8 included. A Prometheus scrape rejects both.
  A series is now keyed on its labels as written, and a byte that is not
  part of a UTF-8 character is written `?` (#3282).
