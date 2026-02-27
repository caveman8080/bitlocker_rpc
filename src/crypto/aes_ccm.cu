// AES-CCM CUDA implementation
#include "aes_ccm.h"
#include "aes256.h"
#include "aes128.h"
#include <cstring>

// Generalized CCM helper: tag length and key length are parameters to public API

__device__ void xor_block(unsigned char *dst, const unsigned char *src, int len) {
    for (int i = 0; i < len; i++) dst[i] ^= src[i];
}

// Decrypt ciphertext using AES-CTR with 12-byte nonce and 32-bit counter in last 4 bytes
// Also compute CBC-MAC over plaintext and return tag (first TAG_LEN bytes of MAC).
// dispatch to AES-128 or AES-256 block encrypt based on key_len
__device__ void aes_block_encrypt_dispatch(const unsigned char *in, unsigned char *out, const unsigned char *key, int key_len) {
    if (key_len == 16) {
        aes128_encrypt_block(in, out, key);
    } else {
        // default to AES-256
        aes_encrypt_block(in, out, key);
    }
}

__device__ bool aes_ccm_decrypt_core(
    const unsigned char *key,
    int key_len,
    const unsigned char *nonce,
    int nonce_len,
    const unsigned char *ciphertext,
    int ciphertext_len,
    unsigned char *plaintext,
    unsigned char *out_tag,
    int tag_len
) {
    unsigned char ctr[16];
    unsigned char mac[16];
    unsigned char block[16];
    int blocks = (ciphertext_len + 15) / 16;

    // Construct counter block layout dynamically to avoid overlapping nonce/counter bytes.
    // Layout: [flags(1)] || nonce(nonce_len) || counter(L)  where 1 + nonce_len + L == 16
    if (nonce_len <= 0 || nonce_len >= 15) {
        // unsupported nonce length for this simple CCM helper
        return false;
    }
    int L = 16 - 1 - nonce_len; // counter size in bytes (1..4)
    if (L < 1 || L > 4) return false;

    // initialize constant part
    ctr[0] = 0x01; // keep legacy flags value; specific CCM flags are not fully modeled here
    // copy nonce into its slot
    memcpy(ctr + 1, nonce, nonce_len);

    // Decrypt ciphertext (CTR mode)
    for (int i = 0; i < blocks; i++) {
        unsigned char keystream[16];
        unsigned int counter = i + 1;
        // place counter in the last L bytes of the block (big-endian)
        for (int b = 0; b < L; ++b) {
            int pos = 16 - L + b;
            ctr[pos] = static_cast<unsigned char>((counter >> (8 * (L - 1 - b))) & 0xFF);
        }
        aes_block_encrypt_dispatch(ctr, keystream, key, key_len);
        int chunk = (i == blocks - 1) ? (ciphertext_len - i * 16) : 16;
        for (int j = 0; j < chunk; j++) {
            plaintext[i * 16 + j] = ciphertext[i * 16 + j] ^ keystream[j];
        }
    }

    // CBC-MAC over plaintext using AES-ECB encrypt of 16-byte blocks
    memset(mac, 0, 16);
    for (int i = 0; i < blocks; i++) {
        int chunk = (i == blocks - 1) ? (ciphertext_len - i * 16) : 16;
        memset(block, 0, 16);
        memcpy(block, plaintext + i * 16, chunk);
        xor_block(mac, block, 16);
        aes_block_encrypt_dispatch(mac, mac, key, key_len);
    }
    // Per RFC-3610, the authentication value U = T XOR first-M-bytes(S_0)
    // where S_0 = E(K, A_0) with counter = 0. Compute S_0 and XOR with T.
    unsigned char s0[16];
    // place counter = 0 in last L bytes
    for (int b = 0; b < L; ++b) {
        int pos = 16 - L + b;
        ctr[pos] = 0x00;
    }
    aes_block_encrypt_dispatch(ctr, s0, key, key_len);
    for (int i = 0; i < tag_len; ++i) out_tag[i] = mac[i] ^ s0[i];
    return true;
}

// Wrapper: encrypted data layout = ciphertext || tag (last TAG_LEN bytes)
__device__ bool aes_ccm_decrypt(const unsigned char *encrypted, int encrypted_len, const unsigned char *key, int key_len, const unsigned char *nonce, int nonce_len, int tag_len, unsigned char *decrypted) {
    if (encrypted_len <= tag_len) return false;
    int ciphertext_len = encrypted_len - tag_len;
    const unsigned char* tag_in = encrypted + ciphertext_len;

    // compute tag
    unsigned char computed_tag[16];
    // call core with key_len and tag_len
    bool ok = aes_ccm_decrypt_core(key, key_len, nonce, nonce_len, encrypted, ciphertext_len, decrypted, computed_tag, tag_len);
    if (!ok) return false;

    // compare tags
    for (int i = 0; i < tag_len; ++i) {
        if (computed_tag[i] != tag_in[i]) return false;
    }
    return true;
}
