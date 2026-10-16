/* Poisoning allocator for the ownership grid (tests/ownership_grid).
 *
 * Linked into a cell's program with
 *   -Wl,--wrap=free,--wrap=realloc,--wrap=aether_numa_free,--wrap=aether_numa_free_aligned
 * so every call of free() and realloc() in the program and in the Aether
 * runtime it links, and every call of the runtime's own NUMA frees (actor
 * blocks and scheduler tables, which go back through _aligned_free or
 * VirtualFree on Windows, out of free()'s reach), reaches the functions
 * below. They pass straight through unless the environment variable
 * OWNERSHIP_GRID_POISON is set, so one build of a cell runs twice: as it is,
 * where the heap count measures leaks, and poisoned. Poisoned, a freed block
 * is:
 *
 *   - filled with 0xDD, so a read of it after the free sees garbage that no
 *     value check accepts (a string compares unequal, a closure environment's
 *     pointers fault);
 *   - never handed back, so no later allocation reuses it and hides a stale
 *     read behind a fresh value;
 *   - recorded, so a second free (or a realloc) of it stops the program with
 *     "POISON: double free" and exit code 86.
 *
 * The table of freed addresses grows as it fills. If it cannot (no memory),
 * the program stops with exit code 87, which the runner reports as a fault of
 * the harness, never as a finding.
 *
 * Poisoned, memory is never given back, so the heap only grows: the grid's
 * runner ignores the growth figure of that run.
 *
 * gcc/ld only: macOS's linker has no --wrap, and the grid builds without
 * this file there. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <malloc.h>
#include <windows.h>
#define POISON_BLOCK_SIZE(p) _msize(p)
#else
#include <malloc.h>
#include <unistd.h>
#define POISON_BLOCK_SIZE(p) malloc_usable_size(p)
#endif

#define POISON_EXIT 86
#define POISON_HARNESS_EXIT 87

void __real_free(void* p);
void* __real_realloc(void* p, size_t n);
void __real_aether_numa_free(void* p, size_t size);
void __real_aether_numa_free_aligned(void* p, size_t size);

/* 1 when OWNERSHIP_GRID_POISON is set. Read with the OS's own call on
 * Windows, which works before the C runtime has set up getenv: free() can
 * run that early, from a constructor. */
static int poisoning(void) {
    static volatile int state = -1;
    if (state < 0) {
#if defined(_WIN32)
        char buf[8];
        state = GetEnvironmentVariableA("OWNERSHIP_GRID_POISON", buf, sizeof buf) > 0;
#else
        state = getenv("OWNERSHIP_GRID_POISON") != NULL;
#endif
    }
    return state;
}

/* Open-addressed set of every freed address, at most half full. Its storage
 * comes from calloc, which is not wrapped, and is never freed. */
static void** g_freed = NULL;
static size_t g_slots = 0;
static size_t g_count = 0;
static volatile int g_lock = 0;

static void lock(void) {
    while (__atomic_exchange_n(&g_lock, 1, __ATOMIC_ACQUIRE)) {
    }
}

static void unlock(void) {
    __atomic_store_n(&g_lock, 0, __ATOMIC_RELEASE);
}

static size_t slot_of(void* p, size_t slots) {
    unsigned long long h = (unsigned long long)(size_t)p >> 4;
    h *= 0x9E3779B97F4A7C15ull;
    return (size_t)(h >> 20) & (slots - 1);
}

static void harness_stop(const char* what) {
    fprintf(stderr, "POISON HARNESS: %s\n", what);
    fflush(stderr);
    _exit(POISON_HARNESS_EXIT);
}

/* Doubles the table (or makes the first one), under the lock. */
static void grow(void) {
    size_t slots = g_slots ? g_slots * 2 : ((size_t)1 << 20);
    void** table = (void**)calloc(slots, sizeof(void*));
    if (!table) harness_stop("no memory to grow the table of freed blocks");
    for (size_t i = 0; i < g_slots; i++) {
        if (!g_freed[i]) continue;
        size_t j = slot_of(g_freed[i], slots);
        while (table[j]) j = (j + 1) & (slots - 1);
        table[j] = g_freed[i];
    }
    /* The old table is leaked on purpose: it is not the program's memory,
     * and handing it to free() would come back here. */
    g_freed = table;
    g_slots = slots;
}

/* 1 when p was freed before; records it when `record` is set. Under the lock. */
static int seen_or_record(void* p, int record) {
    if (!g_freed) grow();
    size_t j = slot_of(p, g_slots);
    while (g_freed[j]) {
        if (g_freed[j] == p) return 1;
        j = (j + 1) & (g_slots - 1);
    }
    if (record) {
        if (g_count + 1 > g_slots / 2) {
            grow();
            j = slot_of(p, g_slots);
            while (g_freed[j]) j = (j + 1) & (g_slots - 1);
        }
        g_freed[j] = p;
        g_count++;
    }
    return 0;
}

static void stop(const char* what, void* p) {
    fprintf(stderr, "POISON: %s of %p\n", what, p);
    fflush(stderr);
    fflush(stdout);
    _exit(POISON_EXIT);
}

/* Records p as freed, or stops on a second free. */
static void record_free(void* p, const char* what) {
    lock();
    int again = seen_or_record(p, 1);
    unlock();
    if (again) stop(what, p);
}

/* The header of a refcounted string (std/string/aether_string_abi.h): the
 * magic word, the count, the length, the capacity and the data pointer. */
#define POISON_STRING_MAGIC 0xAE57C0DEu
#define POISON_STRING_HEADER (4 + 4 + 3 * sizeof(size_t))

void __wrap_free(void* p) {
    if (!poisoning()) {
        __real_free(p);
        return;
    }
    if (!p) return;
    record_free(p, "double free");
    size_t n = POISON_BLOCK_SIZE(p);
    size_t keep = 0;
    /* A freed refcounted string keeps its header. string_release ignores a
     * block without the magic word, so a poisoned header would turn a
     * second release into a silent no-op; kept, the second release frees
     * the block again and stops here. Its characters are still poisoned,
     * which is why the grid's cells compare contents, never only a length. */
    if (n >= POISON_STRING_HEADER) {
        unsigned int magic;
        memcpy(&magic, p, sizeof magic);
        if (magic == POISON_STRING_MAGIC) keep = POISON_STRING_HEADER;
    }
    memset((char*)p + keep, 0xDD, n - keep);
}

void* __wrap_realloc(void* p, size_t n) {
    if (!poisoning()) return __real_realloc(p, n);
    if (!p) return malloc(n);
    lock();
    int freed = seen_or_record(p, 0);
    unlock();
    if (freed) stop("realloc of a freed block", p);
    if (n == 0) {
        __wrap_free(p);
        return NULL;
    }
    size_t old = POISON_BLOCK_SIZE(p);
    void* q = malloc(n);
    if (!q) return NULL;
    memcpy(q, p, old < n ? old : n);
    __wrap_free(p);
    return q;
}

/* The runtime's NUMA frees: an actor's block (aether_numa_free_aligned) and
 * a scheduler table (aether_numa_free). Their blocks come from
 * _aligned_malloc, VirtualAlloc or malloc, so their size is the caller's
 * `size`, not the heap's. */
void __wrap_aether_numa_free_aligned(void* p, size_t size) {
    if (!poisoning()) {
        __real_aether_numa_free_aligned(p, size);
        return;
    }
    if (!p) return;
    record_free(p, "double free of an actor block");
    memset(p, 0xDD, size);
}

void __wrap_aether_numa_free(void* p, size_t size) {
    if (!poisoning()) {
        __real_aether_numa_free(p, size);
        return;
    }
    if (!p) return;
    record_free(p, "double free of a NUMA block");
    memset(p, 0xDD, size);
}
