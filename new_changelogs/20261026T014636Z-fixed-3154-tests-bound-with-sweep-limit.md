- **Shell tests bound their own commands with the sweep's limit, never
  timeout(1).** Five WebSocket drivers ran their client under `timeout 30` or
  `timeout 60`, and `parse_depth_guard` ran aetherc under `timeout 60`. On
  Windows that limit ends a hung native program with a SIGTERM to its MSYS2
  stand-in, the signal that reaches unrelated MSYS2 shells (#2479). On macOS
  without coreutils every deep compile in `parse_depth_guard` exited 127
  without aetherc running, and the test passed. They use
  `sweep_timeout_bound` now, and `check_shell_kills.py` rejects `timeout`,
  `gtimeout` and `kill %N` in `tests/**/*.sh` (#3154).
