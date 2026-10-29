- **Freeing an execution account with live blocks no longer leaves its
  parent charged for them.** The freed account's blocks were detached but
  its ancestors kept their charge for them, even after the blocks
  themselves were freed, so a plugin account that freed its scripts'
  accounts while the host still held their data lost allowance each time
  and tripped `TRIPPED_MEMORY` in the end. Freeing a parent under live
  children left the same charge behind on its own parent. Now freeing an
  account credits its ancestors with what its own live blocks were
  charged, and its children go under its parent, which their blocks were
  charged to all along, and keep narrowing under it (#3408).
