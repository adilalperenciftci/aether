- **Every store through a pointer, a slice or an actor's reference
  publishes what it stores (#3398).** A string field reached through a
  pointer was published (#2919), so two actors that reached it counted
  its string atomically; a struct (`p.doc = d`), an element of an array
  field (`p.docs[i] = d`, `p.names[i] = s`), a whole array field
  (`p.names = arr`), an optional in a struct (`p.inner.tag = s`), a
  slice's element (`xs[i] = d`) and the same parts of another actor's state
  (`k.kept.doc = d`) took their strings with plain counts, which two
  actors then raced on. One rule now decides it for every store emitter.
  An element store also evaluates the element's place once: a string or
  closure element's index used to be evaluated twice. The ownership grid
  has a place for a field of a heap box reached through a pointer (P4H).
