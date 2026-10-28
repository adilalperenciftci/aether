/* `fn(arg)` on a thread of its own with a stack of `bytes`, joined. Apart
 * from chain.c so that it sees the platform's threads even where the runtime
 * is built without them (the cooperative one). 0 when it ran. */

#include <stddef.h>

#ifdef _WIN32
#include <windows.h>

typedef struct {
    void (*fn)(void*);
    void* arg;
} SmallStackJob;

static DWORD WINAPI small_stack_entry(LPVOID p) {
    SmallStackJob* job = (SmallStackJob*)p;
    job->fn(job->arg);
    return 0;
}

int run_on_small_stack(void (*fn)(void*), void* arg, size_t bytes) {
    SmallStackJob job = { fn, arg };
    /* The size reserved, not only committed: the thread's whole stack. */
    HANDLE t = CreateThread(NULL, bytes, small_stack_entry, &job,
                            STACK_SIZE_PARAM_IS_A_RESERVATION, NULL);
    if (!t) return -1;
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);
    return 0;
}
#else
#include <pthread.h>

typedef struct {
    void (*fn)(void*);
    void* arg;
} SmallStackJob;

static void* small_stack_entry(void* p) {
    SmallStackJob* job = (SmallStackJob*)p;
    job->fn(job->arg);
    return NULL;
}

int run_on_small_stack(void (*fn)(void*), void* arg, size_t bytes) {
    SmallStackJob job = { fn, arg };
    pthread_attr_t attr;
    pthread_t t;
    if (pthread_attr_init(&attr) != 0) return -1;
    if (pthread_attr_setstacksize(&attr, bytes) != 0) {
        pthread_attr_destroy(&attr);
        return -1;
    }
    int rc = pthread_create(&t, &attr, small_stack_entry, &job);
    pthread_attr_destroy(&attr);
    if (rc != 0) return -1;
    pthread_join(t, NULL);
    return 0;
}
#endif
