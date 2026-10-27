- **A core's overflow flush is not entered again from a step it makes.** Its
  own-core path steps actors before it takes their entries off the buffer,
  and a step that flushed in turn (an inline send, an ask's relief) delivered
  those entries a second time. A flush under way now finishes alone, and the
  flag that says the buffers hold anything is worked out from the buffers, so
  an entry appended during a flush is not hidden from the next (#3247).
