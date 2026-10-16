- **A trusted function's own `sandbox.enforce` no longer takes the block's
  grants with it.** In `sandbox.enforce(perms, svc) { svc.read() }`, the
  trusted call dropped the sandbox stack to its site's level and put the
  depth back after. If `svc.read` then wrote an enforce of its own, as an
  injected service keeping a fixed-path fence does, that enforce pushed into
  the level the call had dropped, over the block's grants, and freed what it
  pushed when it ended. From then on the block was checked against freed
  memory: a service called three times read once and was refused twice,
  and valgrind reported invalid reads in `_aether_sandbox_check_impl`. With
  the enforce at the outermost level, the inner enforce's end also
  uninstalled the checker for the rest of the block. A trusted call now
  pushes a barrier level above the ones it hides instead of dropping the
  depth, and the checker walks the stack from the top, jumping from a
  barrier to below the level it names, so nothing pushed inside a trusted
  call reaches the block's grants, and a `try` unwinding a panic out of one
  finds them as they were. Covered in `std/sandbox/test_sandbox_trust.ae`
  (a fenced service called three times, and one panicking inside its fence).
