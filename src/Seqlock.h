#pragma once

#include <atomic>
#include <thread>

// Lock-free seqlock implementation for single writer, multiple readers
// Based on the Linux kernel seqlock
template<typename T>
class Seqlock {
public:
    Seqlock() : sequence_(0) {}

    // Write (called from main thread only)
    void Write(const T& data) {
        // Increment sequence to odd value (write in progress)
        sequence_.fetch_add(1, std::memory_order_acquire);

        // Write the data
        data_ = data;

        // Increment sequence to even value (write complete)
        sequence_.fetch_add(1, std::memory_order_release);
    }

    // Read (called from any thread)
    T Read() const {
        T result;
        uint64_t seq1, seq2;

        do {
            // Read sequence before reading data
            seq1 = sequence_.load(std::memory_order_acquire);

            // If sequence is odd, a write is in progress, spin
            while (seq1 & 1) {
                std::this_thread::yield();
                seq1 = sequence_.load(std::memory_order_acquire);
            }

            // Read the data
            result = data_;

            // Memory fence
            std::atomic_thread_fence(std::memory_order_acquire);

            // Read sequence after reading data
            seq2 = sequence_.load(std::memory_order_acquire);

            // If sequences don't match, data was modified during read, retry
        } while (seq1 != seq2);

        return result;
    }

    // Get current sequence number
    uint64_t GetSequence() const {
        return sequence_.load(std::memory_order_relaxed);
    }

private:
    std::atomic<uint64_t> sequence_;
    T data_;
};
