- **A stop closes the connections still waiting for their first bytes.** In
  actor dispatch mode a connection accepted before its request arrived
  waits in the accept poller, and when the server stopped it was left open
  with no owner: a descriptor lost per connection, and a client that never
  saw the server go. The accept loop now closes them as it ends (#3204).
