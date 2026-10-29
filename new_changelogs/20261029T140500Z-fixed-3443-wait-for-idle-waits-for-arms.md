- **`wait_for_idle()` waits for a receive timeout's arm to end.** The step
  that fires a countdown disarms it before the arm runs, and
  `wait_for_idle()` saw a timeout only while it was armed, so it returned
  while the arm still ran, and a program read the arm's state before the arm
  wrote it. A step that fires a countdown is now counted until its arm
  returns (#3443).
