- **Deeply nested sandbox blocks now fail closed.** The generated permission
  stack silently dropped pushes beyond its 64-slot capacity, so an inner
  policy could run under only its outer grants. The logical depth now
  continues past the storage limit and refuses checks until matching pops or
  unwind restoration returns it to a representable level.
