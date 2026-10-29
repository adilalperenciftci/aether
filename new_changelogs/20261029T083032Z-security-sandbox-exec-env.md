- **Sandbox controls now survive `execve` with an explicit environment.** The
  preload layer rebuilds child environments with its current `LD_PRELOAD` and
  grant-source entries, preventing an explicit `envp` from dropping or
  replacing cross-process containment.
