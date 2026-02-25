#pragma once
#include <atomic>
#include <thread>
#include <chrono>

extern bool running;
extern unsigned long long total_candidates_tested;
void display_progress();
void display_gpu_utilization();
