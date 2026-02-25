#pragma once
#include <cstddef>

__device__ void pbkdf2_hmac_sha256(const unsigned char *pass, size_t passlen, const unsigned char *salt, size_t saltlen, int iterations, unsigned char *dk, size_t dklen);
