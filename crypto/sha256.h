#pragma once
#include <cstddef>

__device__ void sha256(const unsigned char *data, size_t len, unsigned char *hash);
__device__ void sha256_init(uint32_t *h);
__device__ void sha256_transform(const unsigned char *data, uint32_t *h);
