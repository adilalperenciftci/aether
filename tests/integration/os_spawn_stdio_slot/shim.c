/* For probe.ae (#3209): puts a close-on-exec pipe end on fd 1, the slot a
 * closed stdout leaves, as another thread's spawn pipe takes it, and tells
 * whether a child spawned meanwhile kept it. */

#if defined(_WIN32)

int stdio_slot_take(void) { return -1; }
int stdio_slot_child_kept(int read_fd) { (void)read_fd; return -1; }

#else

#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

static int g_saved_stdout = -1;

/* Moves this process's stdout aside and puts the write end of a new
 * close-on-exec pipe on fd 1. Returns the read end, or -1. Nothing may be
 * printed until stdio_slot_child_kept puts stdout back. */
int stdio_slot_take(void) {
    int p[2];
    if (pipe(p) != 0) return -1;
    g_saved_stdout = fcntl(1, F_DUPFD_CLOEXEC, 3);
    if (g_saved_stdout < 0) return -1;
    close(1);
    int w = fcntl(p[1], F_DUPFD_CLOEXEC, 1);   /* the lowest free from 1: fd 1 */
    close(p[1]);
    if (w != 1) return -1;
    fcntl(p[0], F_SETFD, FD_CLOEXEC);
    return p[0];
}

/* Closes this process's write end (fd 1) and puts stdout back. 1 when a
 * child still holds the write end (no EOF within a second), 0 when it does
 * not, -1 on an error. */
int stdio_slot_child_kept(int read_fd) {
    close(1);
    if (g_saved_stdout >= 0) {
        dup2(g_saved_stdout, 1);
        close(g_saved_stdout);
        g_saved_stdout = -1;
    }
    struct pollfd pfd = { read_fd, POLLIN, 0 };
    int r = poll(&pfd, 1, 1000);
    if (r < 0) return -1;
    if (r == 0) {
        close(read_fd);
        return 1;   /* no EOF: a writer is still open */
    }
    char b;
    ssize_t n = read(read_fd, &b, 1);
    close(read_fd);
    return n == 0 ? 0 : 1;
}

#endif
