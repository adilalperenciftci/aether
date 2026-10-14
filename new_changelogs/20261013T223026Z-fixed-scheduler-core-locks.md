- **Stopping the scheduler destroys each core's locks, so a scheduler run
  again leaks nothing on Windows.** `scheduler_init()` made each core's park
  and foreign-send locks again without the previous run's being destroyed.
  On Windows a critical section that has been contended holds a 48-byte heap
  block until it is deleted, so every run in which a wake met a core at its
  park, or two threads off the cores sent at once, lost one per lock. The
  scheduler teardown heap test failed the 0.813.0 Windows release build with
  it (240 then 480 bytes) and about one run in 40 locally. The locks are now
  destroyed with the core tables, and a new test contends a core's lock in
  every cycle, so the loss shows on each run instead of by chance.
