- **Mutually recursive functions agree on what they hand over.** A return
  classifier answers no for a function it is still classifying, and a
  function classified from that answer kept it, so of two tuple functions
  calling each other one could hand an error string the other built over as
  borrowed, and every caller leaked it (std.message's `parse` on a bad
  pattern). An answer that rested on such a no is now kept only while the
  function it rested on is being classified (#2870).
