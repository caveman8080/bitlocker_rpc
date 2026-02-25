#pragma once
#include <cuda_runtime.h>

__global__ void brute_force_kernel(
    unsigned char* salt, int salt_len, int iterations,
    unsigned char* nonce, int nonce_len,
    unsigned char* encrypted_data, int encrypted_len,
    unsigned long long start_index, int* found_flag,
    unsigned char* result_password);

__device__ void recovery_password_to_key(const unsigned char *password, const unsigned char *salt, int salt_len, int iterations, unsigned char *key);
__device__ bool verify_decrypted(const unsigned char* decrypted, size_t len);
