- **A message's string field built from an ask's reply or an `or` leaves
  nothing behind.** `sink ! Note { text: srv ? Name {} }` and
  `sink ! Note { text: word(7) or "dflt" }` leaked the string the field was
  copied from at every send: the field kept a list of its own of what counts
  as a fresh string. It takes the one list now (#3206).
