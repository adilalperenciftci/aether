#ifndef AETHER_FATAL_H
#define AETHER_FATAL_H

/* Before the runtime ends the process on an error it cannot return (#3435):
 * the program's own lines first. stdout is fully buffered when it is a file
 * or a pipe, and abort() flushes no stdio stream on glibc, musl or bionic,
 * so what the program printed last was lost behind the error's message.
 *
 * The flush waits for another thread that holds stdout, a little: a thread
 * in the middle of a println holds its lock for microseconds, and is waited
 * for; one blocked writing to a pipe that nobody reads holds it for as long
 * as that lasts, and the abort must not wait on it, so after a quarter of a
 * second the flush is given up. POSIX tries the lock (flockfile's lock is
 * recursive, so the flush inside it takes it again). Windows' C runtime has
 * no such try, and a build without threads (wasi and Emscripten among them)
 * has no other thread, so they flush. Where abort() flushes the streams
 * itself (macOS, FreeBSD), that flush is the C library's, and waits as it
 * waits. Not for a signal handler: none of this is async-signal-safe. */

#include <stdio.h>
#if !(defined(_WIN32) || defined(AETHER_NO_THREADING) || defined(__wasi__) || defined(__EMSCRIPTEN__))
#  include <time.h>
#endif

static inline void aether_fatal_flush(void) {
#if defined(_WIN32) || defined(AETHER_NO_THREADING) || defined(__wasi__) || defined(__EMSCRIPTEN__)
    fflush(stdout);
#else
    struct timespec start, now;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (;;) {
        if (ftrylockfile(stdout) == 0) {
            fflush(stdout);
            funlockfile(stdout);
            return;
        }
        clock_gettime(CLOCK_MONOTONIC, &now);
        long long waited_ns = (long long)(now.tv_sec - start.tv_sec) * 1000000000LL + (now.tv_nsec - start.tv_nsec);
        if (waited_ns >= 250000000LL) return;
        struct timespec ms = { 0, 1000000 };
        nanosleep(&ms, NULL);
    }
#endif
}

#endif /* AETHER_FATAL_H */
