/**
 * A runtime mutex on Windows allocates nothing once it is made (#3346).
 *
 * InitializeCriticalSection attaches a debug record to the lock the first
 * time a thread has to wait on it: 48 bytes from the process heap, at some
 * arbitrary later point, for each lock. heap_in_use counts every block on
 * Windows, so an exact leak check (std.mem.steady_growth) read the record of
 * a lock first contended inside a measured window as growth, and a program
 * that spawned and released actors failed it now and then. pthread_mutex_init
 * makes the critical section without one (CRITICAL_SECTION_NO_DEBUG_INFO),
 * so contention changes nothing on the heap.
 *
 * The lock is made, held, and waited on by a second thread; its DebugInfo
 * must still be the "none" marker it starts with. Before the fix it was a
 * record after the wait.
 */

#include "test_harness.h"
#include "../../runtime/utils/aether_thread.h"

#ifdef _WIN32
#include <windows.h>

static pthread_mutex_t g_contended;
static volatile LONG g_waiter_started;

static DWORD WINAPI wait_for_lock(void* arg) {
    (void)arg;
    InterlockedExchange(&g_waiter_started, 1);
    pthread_mutex_lock(&g_contended);
    pthread_mutex_unlock(&g_contended);
    return 0;
}

TEST(win_mutex_contention_allocates_no_debug_record) {
    g_waiter_started = 0;
    pthread_mutex_init(&g_contended, NULL);
    CRITICAL_SECTION* cs = (CRITICAL_SECTION*)&g_contended;
    PRTL_CRITICAL_SECTION_DEBUG at_init = cs->DebugInfo;

    pthread_mutex_lock(&g_contended);
    HANDLE t = CreateThread(NULL, 0, wait_for_lock, NULL, 0, NULL);
    ASSERT_TRUE(t != NULL);
    while (InterlockedCompareExchange(&g_waiter_started, 0, 0) == 0) Sleep(1);
    Sleep(50);   // long enough for the waiter to block on the lock
    pthread_mutex_unlock(&g_contended);
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);

    ASSERT_TRUE(at_init == (PRTL_CRITICAL_SECTION_DEBUG)(LONG_PTR)-1);
    ASSERT_TRUE(cs->DebugInfo == at_init);
    pthread_mutex_destroy(&g_contended);
}
#endif
