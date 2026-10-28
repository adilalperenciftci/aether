- **Actor protocols.** A `protocol` lists the messages a reference to an
  actor may be sent and in which order, as `state -> Message -> state`
  lines; `actor Writer implements FileWriter` promises an arm for each. The
  compiler follows every reference through the function holding it, across
  branches, loops and asks, and refuses a send the protocol does not allow
  in a state the reference may be in (E0600), naming the states and what
  each takes: `Write` after `Close`, `Close` twice around a loop. A
  parameter typed `actor_ref[FileWriter]` takes any actor that implements
  it; a reference passed, copied, stored or captured is followed from an
  unknown state; a bare `actor_ref` follows no protocol. The API pages
  (docgen) now show an exported `message` or `protocol` as declared (#385).
