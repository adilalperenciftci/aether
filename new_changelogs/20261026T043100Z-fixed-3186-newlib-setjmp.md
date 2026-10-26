- **A panic unwinds on newlib and picolibc (ESP-IDF).** The runtime called
  `_longjmp`, which those libcs do not declare, so the panic code and any
  program with a `try` did not compile for ESP32. They use plain
  `setjmp`/`longjmp`, which there save no signal mask (#3186).
