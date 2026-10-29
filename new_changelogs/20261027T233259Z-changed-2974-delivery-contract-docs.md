- **The actor delivery contract is written down.** docs/actor-concurrency.md
  says what a send promises: each sender's messages in order, at most once
  (every message not handled released and counted), unbounded by default
  because a blocked sender can deadlock the scheduler, and a bound when the
  actor asks for one. docs/structured-concurrency.md records Phase 1
  (death notices, links, restart in place, std.supervise) as shipped and
  where it differs from the proposal; Phase 2 stays a proposal. A new
  example, examples/02-actors/12-supervisor.ae, restarts a crashed actor
  under its ref and shows a supervisor giving up (#2974).
