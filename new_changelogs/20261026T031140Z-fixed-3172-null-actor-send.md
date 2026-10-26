- **A send or an ask to a null actor reference panics.** It read the null
  actor's fields and the process died of an access violation, past the
  barrier that catches an actor's panic. Now it is a panic naming the
  operation and the place (`null_actor_send: send to a null actor reference
  at main.ae:12:5`), so a handler's send to an unconnected successor ends
  that actor alone. The WebAssembly and ESP32 builds link the panic code
  they now reach (#3172).
