- **`ae build --emit=lib --package` removes its staging directory.** Each
  run left an `ae-package-<pid>` directory in the temp directory (`%TEMP%`
  on Windows), built or failed. It is removed when ae exits, on every path
  a build ends by (#2899).
