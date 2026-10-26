- **A spawned child keeps only the parent's own standard streams.** When
  the parent had closed fd 1 or 2, the next descriptor it opened took that
  number, another thread's spawn pipe among them, and the child cleared its
  close-on-exec flag and kept it as its stdout or stderr: that spawn then
  waited for this child to exit, or read its output as an errno. A child now
  keeps a close-on-exec descriptor on 0 to 2 only when it is still the file
  the stream was when the process started (#3209).
