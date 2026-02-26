// HMAC-SHA256 CUDA implementation
#include "hmac_sha256.h"
#include "sha256.h"
#include <cstring>

// Conservative per-thread limits. PBKDF2 uses small msg sizes (salt + 4), so 256 is safe.
#define HMAC_MAX_MSG 256

__device__ void hmac_sha256(const unsigned char *key, size_t keylen, const unsigned char *msg, size_t msglen, unsigned char *out) {
    unsigned char kpad[64];
    memset(kpad, 0, 64);
    if (keylen > 64) {
        unsigned char tmp[32];
        sha256(key, keylen, tmp);
        memcpy(kpad, tmp, 32);
    } else {
        memcpy(kpad, key, keylen);
    }

    if (msglen > HMAC_MAX_MSG) {
        // message too large for this device implementation; truncate (shouldn't happen for PBKDF2 usage)
        msglen = HMAC_MAX_MSG;
    }

    unsigned char inner[64 + HMAC_MAX_MSG];
    for (int i = 0; i < 64; i++) inner[i] = kpad[i] ^ 0x36;
    memcpy(inner + 64, msg, msglen);
    unsigned char temp[32];
    sha256(inner, 64 + msglen, temp);

    unsigned char outer[64 + 32];
    for (int i = 0; i < 64; i++) outer[i] = kpad[i] ^ 0x5c;
    memcpy(outer + 64, temp, 32);
    sha256(outer, 64 + 32, out);
}
