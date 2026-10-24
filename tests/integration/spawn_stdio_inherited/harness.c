/* Regression: a child started by os.spawn_proc inherits its parent's standard
 * streams even when the parent has marked them close-on-exec, as Node does for
 * 0, 1 and 2. Without the fix exec closed them, and the child started with no
 * stdin, stdout or stderr: chromedriver, spawned this way from a Node program,
 * could not start Chrome ("Failed to create Chrome process").
 *
 * Aether cannot set close-on-exec from the language, so this is a C harness:
 * it marks 0, 1 and 2 close-on-exec, then drives the real os_spawn_raw on a
 * probe that reports which of its own streams are open. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct { int _0; const char* _1; } tuple_int_string;
extern tuple_int_string os_spawn_raw(const char* prog, void* argv_list, void* env_list);
extern tuple_int_string os_wait_raw(int token);

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <probe-script>\n", argv[0]); return 2; }

    for (int fd = 0; fd <= 2; fd++) {
        int fl = fcntl(fd, F_GETFD);
        if (fl < 0) { printf("FAIL: fd %d is not open in the parent (test setup)\n", fd); return 1; }
        fcntl(fd, F_SETFD, fl | FD_CLOEXEC);
        /* Sanity: the parent really has the flag, so a pass means the child
         * diverged from it. */
        if (!(fcntl(fd, F_GETFD) & FD_CLOEXEC)) { printf("FAIL: could not mark fd %d (test setup)\n", fd); return 1; }
    }

    tuple_int_string sp = os_spawn_raw(argv[1], (void*)0, (void*)0);
    if (sp._0 < 0) { printf("FAIL: spawn: %s\n", sp._1 ? sp._1 : "?"); return 1; }
    tuple_int_string w = os_wait_raw(sp._0);
    if (w._0 != 0) { printf("FAIL: the probe exited %d: a standard stream was closed in the child\n", w._0); return 1; }
    printf("PASS: the spawned child has stdin, stdout and stderr\n");
    return 0;
}
