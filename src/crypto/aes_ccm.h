#pragma once
#include <cuda_runtime.h>

// key_len: length of key in bytes (16 or 32). tag_len: authentication field length in bytes.
__device__ bool aes_ccm_decrypt(const unsigned char *encrypted, int encrypted_len, const unsigned char *key, int key_len, const unsigned char *nonce, int nonce_len, int tag_len, unsigned char *decrypted);
