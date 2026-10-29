- **Two TLS tests no longer fail on Linux and macOS.** The pure server's
  descriptor-ownership probe still used the accept that took a certificate
  and key path, which #3362 replaced with creds loaded once; Windows skips
  it, so it had not been built. The key test left every server it started
  running, and the slowest to start missed its window on a two-core runner.
  The probe uses the creds API, and the key test runs one server at a time
  (#3459).
