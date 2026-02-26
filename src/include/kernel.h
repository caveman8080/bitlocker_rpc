#pragma once
#include <cuda_runtime.h>

__global__ void brute_force_kernel(
    unsigned char* salt, int salt_len, int iterations,
    unsigned char* nonce, int nonce_len,
    unsigned char* encrypted_data, int encrypted_len,
    unsigned long long start_index, unsigned long long candidates_per_launch, int* found_flag,
    unsigned char* result_password,
    unsigned long long* region_cycles, unsigned long long* region_counts);