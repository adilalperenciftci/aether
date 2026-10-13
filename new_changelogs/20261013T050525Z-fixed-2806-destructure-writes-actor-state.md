- **A tuple destructure in a receive arm writes actor state.** `label, seen
  = pair(tag)`, where `label` and `seen` are state fields, declared handler
  locals of those names, so the state kept its old values. The slots now
  write the state, as `label = v` does: a string field takes a string of
  its own and gives back the one it held, a `fn` field a reference of its
  own, and an optional field takes the slot as the optional (#2806).
