/* The process's close-on-exec pipe and its fork (aether_spawn.h, #3046).
 * Moved here from std/os (#2917, #3028), so the runtime's own pipes and
 * contrib/host's take the same rules and the same lock as std.os's. */
#include "aether_spawn.h"
#include "../config/aether_optimization_config.h"

#if !defined(_WIN32) && !defined(__wasi__)

#include <fcntl.h>
#include <unistd.h>

#if defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || \
    defined(__DragonFly__)
/* Declared here as well: glibc declares it only under _GNU_SOURCE. */
int pipe2(int pipefd[2], int flags);
#define AETHER_HAVE_PIPE2 1
#endif

#ifndef AETHER_HAVE_PIPE2
#include "aether_thread.h"
/* #3028: one per process. Pipe creation holds it shared and every fork holds
 * it exclusively, so no fork sees a pipe that is not yet close-on-exec. */
static pthread_rwlock_t aether_fork_lock = PTHREAD_RWLOCK_INITIALIZER;
#endif

int aether_pipe_cloexec(int fds[2]) {
#ifdef AETHER_HAVE_PIPE2
    return pipe2(fds, O_CLOEXEC);
#else
    pthread_rwlock_rdlock(&aether_fork_lock);
    int rc = pipe(fds);
    if (rc == 0) {
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    }
    pthread_rwlock_unlock(&aether_fork_lock);
    return rc == 0 ? 0 : -1;
#endif
}

/* Where std.os runs processes: a build without a filesystem has none to run
 * (its std.os is stubbed whole, Emscripten's and the embedded ones). */
#if AETHER_HAS_PROCESS && AETHER_HAS_FILESYSTEM
pid_t aether_fork(void) {
#ifdef AETHER_HAVE_PIPE2
    return fork();
#else
    pthread_rwlock_wrlock(&aether_fork_lock);
    pid_t pid = fork();
    if (pid != 0) pthread_rwlock_unlock(&aether_fork_lock);
    return pid;
#endif
}
#endif

#endif
