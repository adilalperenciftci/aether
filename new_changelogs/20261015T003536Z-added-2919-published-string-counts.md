- **A string other threads can reach counts atomically.** The runtime
  can publish a counted string (`aether_string_publish`): a bit of its
  count marks it shared, and its retain and release are atomic from then
  on, while every other string keeps its plain count. Stage 3 of the
  ownership model keeps a string by retaining it where it copied, and a
  module `var` or a closure environment can be read by several actors at
  once; their strings are published where they are stored (#2919).
