#pragma once
#include <cuda_runtime.h>
#include <cstdint>

__device__ void sha256_init(uint32_t *h);
__device__ void sha256_transform(const unsigned char *data, uint32_t *h);
__device__ void sha256(const unsigned char *data, size_t len, unsigned char *hash);
// Warp-distributed SHA-256 for identical-message across a warp.
// Requires that `data` points to memory visible to all lanes (shared or global),
// and that all 32 lanes participate. The resulting 32-byte digest is written to
// `hash` on every lane.
__device__ void sha256_warp(const unsigned char *data, size_t len, unsigned char *hash);
