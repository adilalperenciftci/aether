- **`ae build --namespace` removes its temp workspace.** The build writes the
  synthesized script, the describe stub and the generated C to
  `<temp>/aether_ns_<pid>`, and left that directory behind after every
  build, succeeded or failed, so a machine that builds namespaces often
  collected hundreds of them. It is now removed on every way out of the
  build, and one an earlier process with the same pid left is cleared before
  use (#2773).
