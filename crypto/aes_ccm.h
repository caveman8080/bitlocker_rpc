#pragma once
#include <cstddef>

__device__ bool aes_ccm_decrypt(const unsigned char *encrypted, int encrypted_len, const unsigned char *key, const unsigned char *nonce, int nonce_len, unsigned char *decrypted);
