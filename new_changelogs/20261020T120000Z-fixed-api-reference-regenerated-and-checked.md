- **The API reference matches std again, and CI keeps it that way.**
  `docs/api` is generated from std by `tools/docgen` and committed, but
  nothing regenerated it when std's exports changed: it still documented
  the hundreds of names one name per operation removed (#2976, #3014) and
  had no page for std.quote. It is regenerated, `make docs` now clears the
  folder first so a removed module's page cannot linger, and the new
  `make check-api-docs` (run by `make check-docs` on every CI leg)
  regenerates the reference into a temporary folder and names each page
  that differs from the committed one.
