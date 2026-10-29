#ifndef AETHER_FATAL_H
#define AETHER_FATAL_H

/* Before the runtime ends the process on an error it cannot return (#3435):
 * the program's own lines first. stdout is fully buffered when it is a file
 * or a pipe, and abort() flushes no stdio stream on glibc, so what the
 * program printed last was lost behind the error's message.
 *
 * Only when no other thread holds stdout: one blocked writing to a pipe that
 * nobody reads holds its lock for as long as that lasts, and the abort must
 * not wait on it. POSIX tries the lock (flockfile's lock is recursive, so the
 * flush inside it takes it again); Windows' C runtime has no such try, and a
 * build without threads (wasi and Emscripten among them) has no other
 * thread, so they flush. Not for a signal handler: neither call is
 * async-signal-safe. */

#include <stdio.h>

static inline void aether_fatal_flush(void) {
#if defined(_WIN32) || defined(AETHER_NO_THREADING) || defined(__wasi__) || defined(__EMSCRIPTEN__)
    fflush(stdout);
#else
    if (ftrylockfile(stdout) == 0) {
        fflush(stdout);
        funlockfile(stdout);
    }
#endif
}

#endif /* AETHER_FATAL_H */
