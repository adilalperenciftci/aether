// spawn_sandboxed_bsd.c — spawn a child process under Aether sandbox (FreeBSD)
//
// Same model as the Linux backend: fork, shm_open, and LD_PRELOAD —
// FreeBSD's rtld-elf honors LD_PRELOAD and dlsym(RTLD_NEXT, ...) just
// as glibc's loader does. The one platform difference is locating the
// running binary: FreeBSD does not mount /proc by default, so instead
// of readlink("/proc/self/exe") we ask the kernel directly via
// sysctl(KERN_PROC_PATHNAME).
//
// Containment here is two-layered: the LD_PRELOAD preload library for
// any child, plus AETHER_CAPSICUM=1 so an Aether child additionally
// self-sandboxes with cap_enter() (kernel-enforced) via its startup
// hook. See the child-branch comment below and capsicum_autosandbox.c.
//
// Self-guarded: compiles to an empty object off FreeBSD. Companion
// backends: spawn_sandboxed_linux.c, spawn_sandboxed_stub.c.

#if defined(__FreeBSD__)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <fcntl.h>

// From libaether.a — list operations
extern int list_size(void*);
extern void* list_get_raw(void*, int);
// String-ABI accessor: list_get_raw may return a magic AetherString* or a
// raw const char*; aether_string_data unwraps both to a plain C-string.
// Required for grant-pattern reads — see issue #688 (the Linux backend hit
// the same corruption when it cast list_get_raw directly to const char*).
extern const char* aether_string_data(const void*);

// The preload library's lookup, shared with the contrib process hosts.
#include "aether_sandbox_preload_path.h"

// Serialize grants from a list to shared memory
// Format: "category:pattern\n" lines, null-terminated
static char shm_name[64];

static int serialize_grants(void* grant_list) {
    int n = list_size(grant_list);
    if (n <= 0 || n % 2 != 0) return -1;

    // Build the grant string
    char buf[8192];
    int pos = 0;
    for (int i = 0; i < n && pos < 8000; i += 2) {
        const char* cat = aether_string_data(list_get_raw(grant_list, i));
        const char* pat = aether_string_data(list_get_raw(grant_list, i + 1));
        if (!cat || !pat) continue;
        pos += snprintf(buf + pos, sizeof(buf) - pos, "%s:%s\n", cat, pat);
    }

    // Write to shared memory
    snprintf(shm_name, sizeof(shm_name), "/aether_sandbox_%d", getpid());
    int fd = shm_open(shm_name, O_CREAT | O_RDWR, 0600);
    if (fd < 0) return -1;

    if (ftruncate(fd, pos + 1) != 0) {
        close(fd);
        shm_unlink(shm_name);
        return -1;
    }
    void* mem = mmap(NULL, pos + 1, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mem == MAP_FAILED) { close(fd); return -1; }

    memcpy(mem, buf, pos + 1);
    munmap(mem, pos + 1);
    close(fd);

    return 0;
}

// Spawn a sandboxed child process
// Returns: child exit code, or -1 on error
int aether_spawn_sandboxed(void* grant_list, const char* program, const char* arg) {
    // Find the preload library
    char preload_path[1024];
    char tried[2048];
    if (!aether_sandbox_find_preload(preload_path, sizeof(preload_path), tried, sizeof(tried))) {
        aether_sandbox_preload_missing("[aether]", tried);
        return -1;
    }

    // Serialize grants to shared memory
    if (serialize_grants(grant_list) < 0) {
        fprintf(stderr, "[aether] cannot create shared memory for grants\n");
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        shm_unlink(shm_name);
        return -1;
    }

    if (pid == 0) {
        // Child: set up LD_PRELOAD and grant source, then exec
        setenv("LD_PRELOAD", preload_path, 1);
        setenv("AETHER_SANDBOX_SHM", shm_name, 1);
        setenv("AETHER_SANDBOX_VERBOSE", "0", 0);

        // Two-layer containment on FreeBSD:
        //   1. LD_PRELOAD (above) — intercepts libc for ANY child,
        //      including non-Aether programs (python3, bash). Userspace,
        //      cooperative, bypassable by raw syscalls / static binaries.
        //   2. AETHER_CAPSICUM=1 — if the child is itself an Aether
        //      binary, its startup hook (capsicum_autosandbox.c) calls
        //      cap_enter() after rtld has loaded, giving kernel-enforced,
        //      unbypassable containment. A non-Aether child simply
        //      ignores the variable, falling back to layer 1.
        //
        // We cannot cap_enter() the child from here ourselves:
        // cap_enter() forbids the runtime linker, so a dynamically
        // linked child would fail to exec. Self-sandboxing after exec is
        // the only model that works — see capsicum_autosandbox.c.
        setenv("AETHER_CAPSICUM", "1", 1);

        if (arg) {
            execlp(program, program, arg, NULL);
        } else {
            execlp(program, program, NULL);
        }
        perror("exec");
        _exit(127);
    }

    // Parent: wait for child
    int status = 0;
    waitpid(pid, &status, 0);

    // Cleanup shared memory
    shm_unlink(shm_name);

    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return -1;
}

#endif // __FreeBSD__
