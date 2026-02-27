// Optimized PBKDF2-HMAC-SHA256 CUDA implementation
#include "pbkdf2.h"
#include "hmac_sha256.h"
#include "sha256.h"
#include <cstring>

// Keep PBKDF2 helpers as device functions (avoid aggressive force-inlining
// which can bloat code size and hurt occupancy). We still use __restrict__ on
// pointers for safer optimization hints.
#define FORCE_INLINE __device__

// This implementation avoids repeated key-processing inside HMAC by
// computing the key block (kpad) once per call and reusing inner/outer
// pads for each HMAC invocation. It follows the PBKDF2 definition.
// To support reasonable salt sizes on-device, we allow salts up to SALT_MAX bytes.
#define SALT_MAX 256
FORCE_INLINE void pbkdf2_hmac_sha256(const unsigned char * __restrict__ pass, size_t passlen, const unsigned char * __restrict__ salt, size_t saltlen, int iterations, unsigned char * __restrict__ dk, size_t dklen) {
    if (saltlen > SALT_MAX) {
        // Salt too large for on-device implementation; zero output and return.
        // Caller should validate salt sizes; returning zeros prevents use of uninitialized key material.
        for (size_t i = 0; i < dklen; ++i) dk[i] = 0;
        return;
    }

    unsigned char kpad[64];
    unsigned char keyhash[32];
    // prepare kpad
    if (passlen > 64) {
        // key too long: kpad = SHA256(pass)
        sha256(pass, passlen, keyhash);
        memset(kpad, 0, 64);
        memcpy(kpad, keyhash, 32);
    } else {
        memset(kpad, 0, 64);
        memcpy(kpad, pass, passlen);
    }

    unsigned char ipad[64];
    unsigned char opad[64];
    for (int i = 0; i < 64; ++i) {
        ipad[i] = kpad[i] ^ 0x36;
        opad[i] = kpad[i] ^ 0x5c;
    }

    unsigned char buf[SALT_MAX + 4]; // salt + block counter
    if (saltlen > 0) memcpy(buf, salt, saltlen);

    // Reusable buffers to avoid repeated stack alloc/copies
    unsigned char inner_base[64 + SALT_MAX + 4]; // ipad || data
    unsigned char outer_base[64 + 32]; // opad || U
    // copy fixed ipad/opad prefix
    for (int i = 0; i < 64; ++i) inner_base[i] = ipad[i];
    for (int i = 0; i < 64; ++i) outer_base[i] = opad[i];

    int block = 1;
    size_t out_off = 0;
    while (out_off < dklen) {
        // set block counter in big-endian
        buf[saltlen + 0] = static_cast<unsigned char>((block >> 24) & 0xFF);
        buf[saltlen + 1] = static_cast<unsigned char>((block >> 16) & 0xFF);
        buf[saltlen + 2] = static_cast<unsigned char>((block >> 8) & 0xFF);
        buf[saltlen + 3] = static_cast<unsigned char>((block) & 0xFF);

        // prepare inner = ipad || (salt||block)
        // copy salt||counter into inner_base after ipad
        memcpy(inner_base + 64, buf, saltlen + 4);
        unsigned char u[32];
        sha256(inner_base, 64 + saltlen + 4, u);

        // compute outer = opad || U1 by copying U into outer_base
        memcpy(outer_base + 64, u, 32);
        unsigned char t[32];
        sha256(outer_base, 64 + 32, t);

        // tmp = U1
        unsigned char tmp[32];
        for (int i = 0; i < 32; ++i) tmp[i] = t[i];

        // iterate for iterations > 1
        for (int iter = 1; iter < iterations; ++iter) {
            // inner = ipad || U_i (reuse inner_base)
            memcpy(inner_base + 64, t, 32);
            sha256(inner_base, 64 + 32, u);
            // outer = opad || U_i
            memcpy(outer_base + 64, u, 32);
            sha256(outer_base, 64 + 32, t);
            // XOR into tmp
            for (int i = 0; i < 32; ++i) tmp[i] ^= t[i];
        }

        size_t to_copy = (dklen - out_off > 32) ? 32 : (dklen - out_off);
        memcpy(dk + out_off, tmp, to_copy);
        out_off += to_copy;
        block++;
    }
}

// PBKDF2 using precomputed ipad/opad arrays
__device__ void pbkdf2_hmac_sha256_with_pads(const unsigned char * __restrict__ ipad, const unsigned char * __restrict__ opad, const unsigned char * __restrict__ salt, size_t saltlen, int iterations, unsigned char * __restrict__ dk, size_t dklen) {
    unsigned char buf[64 + 4]; // salt + counter
    if (saltlen > 64) {
        // unsupported salt length for this simple device impl: zero output and return
        for (size_t i = 0; i < dklen; ++i) dk[i] = 0;
        return;
    }
    if (saltlen > 0) memcpy(buf, salt, saltlen);

    unsigned char inner_base[64 + 64];
    unsigned char outer_base[64 + 32];
    // copy ipad/opad into bases
    for (int i = 0; i < 64; ++i) inner_base[i] = ipad[i];
    for (int i = 0; i < 64; ++i) outer_base[i] = opad[i];

    int block = 1;
    size_t out_off = 0;
    while (out_off < dklen) {
        buf[saltlen + 0] = static_cast<unsigned char>((block >> 24) & 0xFF);
        buf[saltlen + 1] = static_cast<unsigned char>((block >> 16) & 0xFF);
        buf[saltlen + 2] = static_cast<unsigned char>((block >> 8) & 0xFF);
        buf[saltlen + 3] = static_cast<unsigned char>((block) & 0xFF);

        memcpy(inner_base + 64, buf, saltlen + 4);
        unsigned char u[32];
        sha256(inner_base, 64 + saltlen + 4, u);

        memcpy(outer_base + 64, u, 32);
        unsigned char t[32];
        sha256(outer_base, 64 + 32, t);

        unsigned char tmp[32];
        for (int i = 0; i < 32; ++i) tmp[i] = t[i];

        for (int iter = 1; iter < iterations; ++iter) {
            memcpy(inner_base + 64, t, 32);
            sha256(inner_base, 64 + 32, u);
            memcpy(outer_base + 64, u, 32);
            sha256(outer_base, 64 + 32, t);
            for (int i = 0; i < 32; ++i) tmp[i] ^= t[i];
        }

        size_t to_copy = (dklen - out_off > 32) ? 32 : (dklen - out_off);
        memcpy(dk + out_off, tmp, to_copy);
        out_off += to_copy;
        block++;
    }
}

// Warp-cooperative PBKDF2: compute ipad/opad once per warp (lane 0) and broadcast to lanes
__device__ void pbkdf2_hmac_sha256_warp(const unsigned char * __restrict__ pass, size_t passlen, const unsigned char * __restrict__ salt, size_t saltlen, int iterations, unsigned char * __restrict__ dk, size_t dklen) {
    // determine lane within warp
    unsigned int mask = 0xffffffffu;
    int lane = threadIdx.x & 31;

    // Allocate a per-block shared pool and derive per-warp pointers from it.
    // 8192 bytes total -> 256 bytes per warp for up to 32 warps per block.
    __shared__ unsigned char s_shared_pool[8192];
    int warpIdInBlock = threadIdx.x / 32;
    int warpsInBlock = (blockDim.x + 31) / 32;
    const int MAX_WARPS_SUPPORTED = 32;
    if (warpsInBlock > MAX_WARPS_SUPPORTED) {
        // Block has more warps than shared pool supports; fail deterministically by zeroing output.
        if (lane == 0) {
            for (size_t i = 0; i < dklen; ++i) dk[i] = 0;
        }
        __syncwarp(mask);
        return;
    }
    unsigned char *s_ipad = s_shared_pool + warpIdInBlock * 256; // 64 bytes
    unsigned char *s_opad = s_ipad + 64; // next 64 bytes
    unsigned char *s_inner = s_opad + 64; // remaining for inner buffer
    unsigned char *s_outer = s_inner + 128;

    if (lane == 0) {
        unsigned char kpad[64];
        if (passlen > 64) {
            unsigned char keyhash[32];
            sha256(pass, passlen, keyhash);
            memset(kpad, 0, 64);
            memcpy(kpad, keyhash, 32);
        } else {
            memset(kpad, 0, 64);
            memcpy(kpad, pass, passlen);
        }
        for (int i = 0; i < 64; ++i) {
            s_ipad[i] = kpad[i] ^ 0x36;
            s_opad[i] = kpad[i] ^ 0x5c;
        }
    }
    __syncwarp(mask);

    unsigned char buf[64 + 4];
    if (saltlen > 0) memcpy(buf, salt, saltlen);

    int block = 1;
    size_t out_off = 0;
    while (out_off < dklen) {
        buf[saltlen + 0] = static_cast<unsigned char>((block >> 24) & 0xFF);
        buf[saltlen + 1] = static_cast<unsigned char>((block >> 16) & 0xFF);
        buf[saltlen + 2] = static_cast<unsigned char>((block >> 8) & 0xFF);
        buf[saltlen + 3] = static_cast<unsigned char>((block) & 0xFF);

        // lane 0 writes inner_base (ipad || salt||counter) into shared memory
        if (lane == 0) {
            for (int i = 0; i < 64; ++i) s_inner[i] = s_ipad[i];
            for (size_t i = 0; i < saltlen + 4; ++i) s_inner[64 + i] = buf[i];
        }
        __syncwarp();

        unsigned char u[32];
        // compute U1 across warp
        sha256_warp(s_inner, 64 + saltlen + 4, u);

        // prepare outer by placing U into shared outer buffer (lane 0)
        if (lane == 0) {
            for (int i = 0; i < 64; ++i) s_outer[i] = s_opad[i];
            for (int i = 0; i < 32; ++i) s_outer[64 + i] = u[i];
        }
        __syncwarp();

        unsigned char t[32];
        sha256_warp(s_outer, 64 + 32, t);

        unsigned char tmp[32];
        for (int i = 0; i < 32; ++i) tmp[i] = t[i];

        for (int iter = 1; iter < iterations; ++iter) {
            // inner = ipad || U_i (write into s_inner by lane 0)
            if (lane == 0) {
                for (int i = 0; i < 64; ++i) s_inner[i] = s_ipad[i];
                for (int i = 0; i < 32; ++i) s_inner[64 + i] = t[i];
            }
            __syncwarp();

            unsigned char u2[32];
            sha256_warp(s_inner, 64 + 32, u2);

            if (lane == 0) {
                for (int i = 0; i < 64; ++i) s_outer[i] = s_opad[i];
                for (int i = 0; i < 32; ++i) s_outer[64 + i] = u2[i];
            }
            __syncwarp();

            sha256_warp(s_outer, 64 + 32, t);
            for (int i = 0; i < 32; ++i) tmp[i] ^= t[i];
        }

        size_t to_copy = (dklen - out_off > 32) ? 32 : (dklen - out_off);
        // copy tmp to dk (per-thread result)
        memcpy(dk + out_off, tmp, to_copy);
        out_off += to_copy;
        block++;
    }
}
