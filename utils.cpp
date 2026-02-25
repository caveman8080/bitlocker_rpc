#include "utils.h"
#include <iostream>
#include <thread>
#include <chrono>

bool running = true;
unsigned long long total_candidates_tested = 0;

void display_progress() {
    while (running) {
        std::cout << "Total candidates tested: " << total_candidates_tested << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(10));
    }
}

void display_gpu_utilization() {
    while (running) {
        std::cout << "GPU Utilization: ";
        system("nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits  ");
        std::this_thread::sleep_for(std::chrono::seconds(10));
    }
}
