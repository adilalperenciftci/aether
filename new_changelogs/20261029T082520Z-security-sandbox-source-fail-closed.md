- **Configured sandbox grant sources now fail closed when unreadable.** The
  preload layer keeps interception active with zero grants when an explicit
  shared-memory or file source is missing, unreadable, or oversized instead
  of silently allowing every operation.
