// AES-128 interface
#pragma once

extern "C" __device__ void aes128_encrypt_block(const unsigned char *in, unsigned char *out, const unsigned char *key);
