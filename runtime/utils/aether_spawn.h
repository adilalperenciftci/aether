#ifndef AETHER_SPAWN_H
#define AETHER_SPAWN_H

/* One discipline for the pipes and forks of a process (#2917, #3028, #3040,
 * #3046), for every part of it that makes either: std.os's process calls,
 * contrib/host's bridges, the scheduler's I/O poller and std.net's and
 * std.http's wake pipes.
 *
 * A pipe made with aether_pipe_cloexec closes on exec in every child. A
 * plain pipe() is copied into every child another thread starts while it is
 * open, and the child keeps it across exec: a capture reading the pipe then
 * waits for EOF until that unrelated child exits, and a wake pipe's write end
 * lives on in it. A child that is meant to keep an end moves it onto its
 * stdio with dup2, which clears the flag on the copy.
 *
 * Where pipe2 is missing (macOS) the flag is set by fcntl after pipe(), and a
 * fork between the two would copy the pipe anyway. Pipe creation then holds
 * the process's fork lock shared and aether_fork holds it exclusively, as the
 * Go runtime's ForkLock does. aether_fork's child inherits the lock held and
 * must exec or _exit without making a pipe.
 *
 * POSIX only: Windows makes HANDLE pipes and has no fork. aether_pipe_cloexec
 * is defined wherever pipe() is (not WASI), aether_fork where std.os runs
 * processes (AETHER_HAS_PROCESS and AETHER_HAS_FILESYSTEM).
 * aether_pipe_cloexec returns 0, or -1 with errno set; aether_fork returns
 * what fork() does. */

#ifndef _WIN32
#include <sys/types.h>

int aether_pipe_cloexec(int fds[2]);
pid_t aether_fork(void);
#endif

#endif
