#pragma once
#include <cuda_runtime.h>

__device__ void pbkdf2_hmac_sha256(const unsigned char * __restrict__ pass, size_t passlen, const unsigned char * __restrict__ salt, size_t saltlen, int iterations, unsigned char * __restrict__ dk, size_t dklen);
__device__ void pbkdf2_hmac_sha256_warp(const unsigned char * __restrict__ pass, size_t passlen, const unsigned char * __restrict__ salt, size_t saltlen, int iterations, unsigned char * __restrict__ dk, size_t dklen);
__device__ void pbkdf2_hmac_sha256_with_pads(const unsigned char * __restrict__ ipad, const unsigned char * __restrict__ opad, const unsigned char * __restrict__ salt, size_t saltlen, int iterations, unsigned char * __restrict__ dk, size_t dklen);
