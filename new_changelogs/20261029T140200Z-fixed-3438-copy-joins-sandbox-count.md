- **A runtime copy joins another copy's sandbox levels before its first
  step.** A step reads only its own copy's word, and a copy that had looked
  nothing up when another copy's count held levels stepped an actor plainly
  inside them; the actor's first check then found levels it could not read
  and was refused. `scheduler_init` now joins another copy's rendezvous of
  this layout, through a pointer the sandbox installs, so the scheduler
  still links nothing of it. A copy whose code runs another copy's panic (a
  library's, under ELF interposition) has its sandbox served by that panic
  and its steps: each copy adds its hooks to a list the panic and the step
  barrier call, where one slot, set by the copy that looked last, served
  only that one, and a panic caught inside another copy's block left its
  level in force (#3438).
