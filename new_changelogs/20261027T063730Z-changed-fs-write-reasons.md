- **`std.fs` and `std.file` write errors say why (#3131).** `fs.write`,
  `fs.write_binary`, `fs.write_atomic`, `fs.rename` and `file.write` returned
  fixed strings (`"write failed"`, `"atomic write failed"`, …) that could not
  tell a missing directory from a full disk or a refusal. They now return the
  path and the OS reason, as `fs.read` already did:
  `/data/out.txt: No such file or directory`, `/dev/full: No space left on
  device`. `fs.rename` names both paths (`a.txt -> b/c.txt: …`), since the
  reason can be the destination's. The reason survives the cleanup after the
  failing call (a close, removing the atomic write's temporary file), a write
  the sandbox refuses reads as `Permission denied` (EACCES, as the sandbox
  preload already reports), and a bad argument keeps the old wording after
  the path.
