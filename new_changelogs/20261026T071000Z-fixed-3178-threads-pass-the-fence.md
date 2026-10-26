- **A child `spawn_sandboxed` starts may run threads, and `grant_fork()`
  lets it start processes.** The kernel fence refused every `clone`, a
  thread's too, so `pthread_create` failed in any child that starts a
  thread: an Aether program with actors, Python with threads, a JVM. The
  grant that lifts the fence, `fork`, was spelt nowhere in std.sandbox, so
  only a hand-built list could hold it. Now a `clone` with `CLONE_THREAD`
  passes the fence. `clone3`, whose flags a filter cannot read, gets
  `ENOSYS`, so libc falls back to `clone`. A new process is still refused
  without a grant, and `sandbox.grant_fork()` grants it. The preload's
  `clone3` wrapper lets a thread through the same way (#3178).
