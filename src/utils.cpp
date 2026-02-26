// Utility functions implementation
// Extracted from bitlocker_rpc.cu
#include "utils.h"
#include <thread>
#include <chrono>
#include <iostream>

extern bool running;
extern unsigned long long total_candidates_tested;

void display_progress() {
    using namespace std::chrono_literals;
    while (running) {
        unsigned long long tested = total_candidates_tested;
        std::cout << "Candidates tested: " << tested << std::endl;
        std::this_thread::sleep_for(1s);
    }
}

void display_gpu_utilization() {
    using namespace std::chrono_literals;
    while (running) {
        // Minimal placeholder: real implementation could call nvidia-smi or NVML.
        std::this_thread::sleep_for(5s);
    }
}