#pragma once

#include <cuda_runtime.h>

__device__ unsigned char get_sbox(unsigned char b);
__device__ void shift_rows(unsigned char *state);
__device__ void aes256_key_expansion(const unsigned char *key, unsigned char *w);
__device__ void add_round_key(unsigned char* state, const unsigned char* round_key);
__device__ void aes_encrypt_block(const unsigned char *in, unsigned char *out, const unsigned char *key);
