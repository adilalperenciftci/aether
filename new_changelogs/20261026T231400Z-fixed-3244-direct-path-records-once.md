- **The proxy event loop records a response once when its direct path
  fails.** On Linux and macOS, when the loop could not build the head of a
  response it answers from the upstream's own bytes (an allocation failure),
  it fell back to the copying path after the response had been recorded, so
  its status was counted twice, the breaker fed twice and the upstream's
  in-flight count decremented twice. It now closes the connection, as a
  failure later on that path already did (#3244).
