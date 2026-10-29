#ifndef AETHER_SANDBOX_SHM_H
#define AETHER_SANDBOX_SHM_H

#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

#define AETHER_SANDBOX_SHM_NAME_SIZE 64
#define AETHER_SANDBOX_SHM_CREATE_ATTEMPTS 128

static atomic_uint aether_sandbox_shm_sequence = 0;

static int aether_sandbox_shm_create(char* name, size_t name_size) {
    for (int attempt = 0; attempt < AETHER_SANDBOX_SHM_CREATE_ATTEMPTS; attempt++) {
        unsigned sequence = atomic_fetch_add_explicit(
            &aether_sandbox_shm_sequence, 1, memory_order_relaxed);
        int written = snprintf(name, name_size, "/aether_sandbox_%ld_%u",
                               (long)getpid(), sequence);
        if (written < 0 || (size_t)written >= name_size) {
            errno = ENAMETOOLONG;
            return -1;
        }

        int fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
        if (fd >= 0) return fd;
        if (errno != EEXIST) return -1;
    }
    errno = EEXIST;
    return -1;
}

static int aether_sandbox_shm_write(char* name, size_t name_size,
                                    const void* data, size_t data_size) {
    int fd = aether_sandbox_shm_create(name, name_size);
    if (fd < 0) return -1;

    if (ftruncate(fd, (off_t)data_size) != 0) {
        int saved = errno;
        close(fd);
        shm_unlink(name);
        errno = saved;
        return -1;
    }

    void* mem = mmap(NULL, data_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mem == MAP_FAILED) {
        int saved = errno;
        close(fd);
        shm_unlink(name);
        errno = saved;
        return -1;
    }

    memcpy(mem, data, data_size);
    if (munmap(mem, data_size) != 0) {
        int saved = errno;
        close(fd);
        shm_unlink(name);
        errno = saved;
        return -1;
    }
    if (close(fd) != 0) {
        int saved = errno;
        shm_unlink(name);
        errno = saved;
        return -1;
    }
    return 0;
}

#endif
