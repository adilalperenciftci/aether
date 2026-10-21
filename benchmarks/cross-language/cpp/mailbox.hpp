// A mailbox for one sending thread and one receiving thread, the C++
// benchmarks' message channel. The C++ standard library has no channel, so
// this is what an expert writes from it: a bounded ring on std::atomic with
// a sequence number in each slot, the same design as c/mailbox.h. Neither
// side reads the other's index; a message moves the cache line of its slot
// and nothing else.
//
// Waiting (FAIRNESS.md, techniques): a receiver that finds its slot empty
// spins up to MAILBOX_SPIN pauses, looking again after 1, 2, 4, ... 64 of
// them, then sleeps on a std::condition_variable until a send wakes it. A
// program whose threads outnumber the cores sets MAILBOX_SPIN to 0 and
// sleeps at once. A sender that finds its slot full spins, then yields: the
// receiver is running then (it sleeps only on an empty slot). C++20's
// std::atomic::wait/notify_one measured slower than the condition variable
// in every pattern, so it is not used.
#ifndef BENCH_MAILBOX_HPP
#define BENCH_MAILBOX_HPP

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <thread>

#ifndef MAILBOX_SPIN
#define MAILBOX_SPIN 1000
#endif

inline void mailbox_pause() {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#elif defined(__aarch64__) || defined(__arm__)
    __asm__ __volatile__("yield");
#endif
}

class Mailbox {
public:
    // capacity: a power of two.
    explicit Mailbox(std::uint64_t capacity = 1)
        : mask_(capacity - 1), slots_(new Slot[capacity]) {
        for (std::uint64_t i = 0; i < capacity; i++) slots_[i].seq.store(i, std::memory_order_relaxed);
    }

    Mailbox(const Mailbox&) = delete;
    Mailbox& operator=(const Mailbox&) = delete;

    void send(std::int64_t value) {
        std::uint64_t t = tail_;
        Slot& s = slots_[t & mask_];
        if (s.seq.load(std::memory_order_acquire) != t) {
            int spun = 0;
            for (int step = 1; s.seq.load(std::memory_order_acquire) != t; step = step < 64 ? step * 2 : 64) {
                if (spun < MAILBOX_SPIN) {
                    for (int i = 0; i < step; i++) mailbox_pause();
                    spun += step;
                } else {
                    std::this_thread::yield();
                }
            }
        }
        s.value = value;
        // Sequentially consistent, with the load of sleeping_ after it and
        // the receiver's store to sleeping_ and load of seq in park(): of the
        // two sides at least one sees the other's store, so a receiver never
        // sleeps on a message nobody wakes it for.
        s.seq.store(t + 1, std::memory_order_seq_cst);
        tail_ = t + 1;
        if (sleeping_.load(std::memory_order_seq_cst)) {
            std::lock_guard<std::mutex> lock(lock_);
            wake_.notify_one();
        }
    }

    std::int64_t receive() {
        std::uint64_t h = head_;
        Slot& s = slots_[h & mask_];
        if (s.seq.load(std::memory_order_acquire) != h + 1) park(s, h + 1);
        std::int64_t value = s.value;
        // Free for the sender's message one lap on.
        s.seq.store(h + mask_ + 1, std::memory_order_release);
        head_ = h + 1;
        return value;
    }

private:
    struct Slot {
        // i: free for the sender's i-th message; i + 1: holds it.
        std::atomic<std::uint64_t> seq{0};
        std::int64_t value = 0;
    };

    // The receiver found slot s empty and waits for its sequence to be
    // `full`: spin, then sleep. It looks again after 1, 2, 4, ... 64 pauses:
    // each look pulls the slot's cache line away from the sender.
    [[gnu::noinline]] void park(Slot& s, std::uint64_t full) {
        int spun = 0;
        for (int step = 1; spun < MAILBOX_SPIN; step = step < 64 ? step * 2 : 64) {
            for (int i = 0; i < step; i++) mailbox_pause();
            spun += step;
            if (s.seq.load(std::memory_order_acquire) == full) return;
        }
        std::unique_lock<std::mutex> lock(lock_);
        sleeping_.store(true, std::memory_order_seq_cst);
        while (s.seq.load(std::memory_order_seq_cst) != full) {
            wake_.wait(lock);
        }
        sleeping_.store(false, std::memory_order_relaxed);
    }

    alignas(64) std::uint64_t head_ = 0;   // the receiver's next message
    alignas(64) std::uint64_t tail_ = 0;   // the sender's next message
    // Where a receiver sleeps; a send reads sleeping_ and touches the rest
    // only when it is set.
    alignas(64) std::atomic<bool> sleeping_{false};
    std::mutex lock_;
    std::condition_variable wake_;
    const std::uint64_t mask_;
    std::unique_ptr<Slot[]> slots_;
};

#endif
