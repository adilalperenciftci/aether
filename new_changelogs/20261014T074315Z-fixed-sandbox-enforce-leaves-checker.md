- **`sandbox.enforce` no longer leaves the sandbox on after its block.** It
  uninstalled the checker before popping its grant list, and uninstall clears
  the checker only when no list is left, so the checker stayed installed for
  the rest of the process. Its check then allowed everything (no list), but
  the path resolution in front of it still ran: after any `enforce`, a fs call
  on a path that cannot be resolved (a dangling symlink, say) was refused
  with "sandbox: cannot read path" outside every sandbox, and
  `fs.fs_is_symlink` on a dangling link said 0. It now pops, then uninstalls,
  so a nested block's end still leaves the outer one in force.
  `examples/audit-demo.ae` and the `sandbox_in_spec_block` test, which spell
  the four builtins out, had the same order and are fixed too. Found by sae,
  whose file services now run each operation under `enforce`.
