#pragma once
#include <cstddef>

__device__ void hmac_sha256(const unsigned char *key, size_t keylen, const unsigned char *msg, size_t msglen, unsigned char *out);
