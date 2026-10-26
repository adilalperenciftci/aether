- **A receive timeout counts down again after every message.** `receive {
  ... } after N -> { ... }` fired only for an actor that never received a
  message: the first one zeroed the interval for good, so the reference's
  Monitor never warned once a heartbeat had come, and a poller whose timeout
  sends itself a Tick ticked once. The interval is kept now. The countdown
  starts at spawn and again when the actor has handled a message, a message
  stops it, and it fires once the interval passes with none waiting. Once it
  has fired, only a message starts it again, so a timeout that sends nothing
  leaves the actor idle and `wait_for_idle()` returns, and `wait_for_idle()`
  no longer waits on the countdown of a dead actor. `site-poller.ae` paces
  its polls with the timeout, and the reference and actor-concurrency.md
  describe the cycle (#3162).
