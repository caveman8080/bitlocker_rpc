#pragma once
#include <cuda_runtime.h>

__device__ void hmac_sha256(const unsigned char *key, size_t keylen, const unsigned char *msg, size_t msglen, unsigned char *out);
