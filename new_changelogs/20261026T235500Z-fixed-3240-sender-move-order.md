- **A sender that moves between cores keeps its messages in order.** A core
  takes in messages through one queue per sending core and drains them in
  index order, so an actor moved (a gather toward a core that sends to it, a
  steal) while a message it sent still waited in a receiver's queue could
  have its next message, sent from its new core, delivered first: a pipeline
  example printed its first item last. A core now moves an actor only while
  nothing sent from it is still on its way (#3240).
