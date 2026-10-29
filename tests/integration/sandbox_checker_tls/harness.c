#include <pthread.h>
#include <stdio.h>

#include "aether_sandbox.h"

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int worker_ready;
static int main_checked;
static int worker_result = -1;

static int deny_all(const char* category, const char* resource) {
    (void)category;
    (void)resource;
    return 0;
}

static int allow_all(const char* category, const char* resource) {
    (void)category;
    (void)resource;
    return 1;
}

static void* worker(void* unused) {
    (void)unused;
    _aether_sandbox_checker = allow_all;

    pthread_mutex_lock(&lock);
    worker_ready = 1;
    pthread_cond_signal(&changed);
    while (!main_checked) pthread_cond_wait(&changed, &lock);
    pthread_mutex_unlock(&lock);

    worker_result = aether_sandbox_check("env", "WORKER_VALUE");
    _aether_sandbox_checker = NULL;
    return NULL;
}

int main(void) {
    _aether_sandbox_checker = deny_all;
    pthread_t thread;
    if (pthread_create(&thread, NULL, worker, NULL) != 0) return 2;

    pthread_mutex_lock(&lock);
    while (!worker_ready) pthread_cond_wait(&changed, &lock);
    pthread_mutex_unlock(&lock);

    int main_result = aether_sandbox_check("env", "MAIN_VALUE");

    pthread_mutex_lock(&lock);
    main_checked = 1;
    pthread_cond_signal(&changed);
    pthread_mutex_unlock(&lock);

    pthread_join(thread, NULL);
    _aether_sandbox_checker = NULL;

    if (main_result != 0 || worker_result != 1) {
        fprintf(stderr, "FAIL checker state crossed threads: main=%d worker=%d\n",
                main_result, worker_result);
        return 1;
    }
    printf("PASS: sandbox checker state is thread-local\n");
    return 0;
}
