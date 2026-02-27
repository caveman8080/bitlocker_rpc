#include "sha256.h"
#include <cstdint>
#include <cstring>

__device__ __constant__ uint32_t k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

__device__ __forceinline__ void sha256_init(uint32_t *h) {
    h[0] = 0x6a09e667; h[1] = 0xbb67ae85; h[2] = 0x3c6ef372; h[3] = 0xa54ff53a;
    h[4] = 0x510e527f; h[5] = 0x9b05688c; h[6] = 0x1f83d9ab; h[7] = 0x5be0cd19;
}

__device__ __forceinline__ void sha256_transform(const unsigned char *data, uint32_t *h) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) {
        w[i] = (data[i * 4] << 24) | (data[i * 4 + 1] << 16) | (data[i * 4 + 2] << 8) | data[i * 4 + 3];
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = (w[i - 15] >> 7 | w[i - 15] << 25) ^ (w[i - 15] >> 18 | w[i - 15] << 14) ^ (w[i - 15] >> 3);
        uint32_t s1 = (w[i - 2] >> 17 | w[i - 2] << 15) ^ (w[i - 2] >> 19 | w[i - 2] << 13) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t s1 = (e >> 6 | e << 26) ^ (e >> 11 | e << 21) ^ (e >> 25 | e << 7);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t temp1 = hh + s1 + ch + k[i] + w[i];
        uint32_t s0 = (a >> 2 | a << 30) ^ (a >> 13 | a << 19) ^ (a >> 22 | a << 10);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = s0 + maj;
        hh = g; g = f; f = e; e = d + temp1; d = c; c = b; b = a; a = temp1 + temp2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

__device__ void sha256(const unsigned char *data, size_t len, unsigned char *hash) {
    uint32_t h[8];
    sha256_init(h);
    size_t off = 0;
    while (len >= 64) {
        sha256_transform(data + off, h);
        off += 64; len -= 64;
    }
    unsigned char buf[64];
    memcpy(buf, data + off, len);
    buf[len] = 0x80;
    if (len > 55) {
        memset(buf + len + 1, 0, 63 - len);
        sha256_transform(buf, h);
        memset(buf, 0, 64);
    } else {
        memset(buf + len + 1, 0, 55 - len);
    }
    uint64_t bitlen = (off + len) * 8;
    buf[56] = bitlen >> 56; buf[57] = bitlen >> 48; buf[58] = bitlen >> 40; buf[59] = bitlen >> 32;
    buf[60] = bitlen >> 24; buf[61] = bitlen >> 16; buf[62] = bitlen >> 8; buf[63] = bitlen;
    sha256_transform(buf, h);
    for (int i = 0; i < 8; i++) {
        hash[i * 4] = h[i] >> 24; hash[i * 4 + 1] = h[i] >> 16;
        hash[i * 4 + 2] = h[i] >> 8; hash[i * 4 + 3] = h[i];
    }
}

// Warp-distributed helper: load message (identical across warp) into shared
// memory using all lanes, let lane 0 compute the SHA256 digest, then broadcast
// the result to all lanes. This is conservative and safe: it parallelizes
// the memory load and uses a single-lane compute, but shares the digest to
// every lane so callers can rely on the hash being present on all lanes.
__device__ void sha256_warp(const unsigned char *data, size_t len, unsigned char *hash) {
    const unsigned int fullMask = 0xffffffffu;
    int lane = threadIdx.x & 31;

    // We only support messages up to 1024 bytes here for simplicity.
    // PBKDF2 HMAC inputs are small (<= 128 bytes) so this is sufficient.
    const int MAX_MSG = 1024;
    if (len > MAX_MSG) {
        if (lane == 0) {
            // fallback to normal sha256 for large messages
            sha256(data, len, hash);
        }
        // broadcast hash from lane 0
        unsigned int *h32 = reinterpret_cast<unsigned int*>(hash);
        for (int i = 0; i < 8; ++i) {
            unsigned int v = 0;
            if ((threadIdx.x & 31) == 0) v = h32[i];
            v = __shfl_sync(fullMask, v, 0);
            h32[i] = v;
        }
        return;
    }

    // shared buffer to hold the message for each warp (max 8 warps supported)
    __shared__ unsigned char s_buf[8192];

    // compute per-warp base pointer in shared buffer: use lane's warp id
    int warpIdInBlock = threadIdx.x / 32;
    // s_buf size = 8192 -> 1024 bytes per warp for up to 8 warps
    const int MAX_WARPS_SUPPORTED = 8;
    bool use_shared_warp_buf = (warpIdInBlock < MAX_WARPS_SUPPORTED);
    unsigned char *warp_buf = s_buf + (use_shared_warp_buf ? (warpIdInBlock * 1024) : 0); // safe pointer if unused

    // If there are more warps in the block than supported, fall back to lane-0-only compute
    if (!use_shared_warp_buf) {
        if (lane == 0) {
            // fallback: compute SHA256 directly from global memory
            unsigned char local_hash[32];
            sha256(data, len, local_hash);
            // broadcast hash from lane 0
            unsigned int *h32 = reinterpret_cast<unsigned int*>(local_hash);
            for (int i = 0; i < 8; ++i) {
                unsigned int v = (lane == 0) ? h32[i] : 0;
                v = __shfl_sync(fullMask, v, 0);
                reinterpret_cast<unsigned int*>(hash)[i] = v;
            }
        } else {
            // non-lane0 lanes still need to receive broadcasted hash
                for (int i = 0; i < 8; ++i) {
                    unsigned int v = 0;
                    v = __shfl_sync(fullMask, v, 0);
                    reinterpret_cast<unsigned int*>(hash)[i] = v;
                }
        }
        return;
    }

    // load message into shared memory using all lanes
    for (size_t off = 0; off < len; off += 4) {
        unsigned int v = 0;
        // lane-local load of up to 4 bytes
        size_t idx = off + lane * 4;
        unsigned char tmp[4] = {0,0,0,0};
        if (idx < len) tmp[0] = data[idx];
        if (idx + 1 < len) tmp[1] = data[idx + 1];
        if (idx + 2 < len) tmp[2] = data[idx + 2];
        if (idx + 3 < len) tmp[3] = data[idx + 3];
        // combine into 32-bit value
        v = (tmp[0] << 24) | (tmp[1] << 16) | (tmp[2] << 8) | tmp[3];
        // lane 0 gathers the pieces via shuffle and writes them sequentially
        unsigned int gathered = __shfl_sync(fullMask, v, 0);
        if (lane == 0) {
            size_t writeOff = off;
            // copy 4 bytes from gathered into warp buffer (respect message end)
            unsigned char *p = reinterpret_cast<unsigned char*>(&gathered);
            for (int k = 0; k < 4 && writeOff + k < len; ++k) warp_buf[writeOff + k] = p[k];
        }
        __syncwarp(fullMask);
    }

    // lane 0 computes the SHA256 over the shared buffer
    unsigned char local_hash[32];
    if (lane == 0) {
        sha256(warp_buf, len, local_hash);
    }

    // broadcast 32-byte hash from lane 0 to all lanes using 32-bit shuffles
    unsigned int *local_hash32 = reinterpret_cast<unsigned int*>(local_hash);
    unsigned int *out32 = reinterpret_cast<unsigned int*>(hash);
    for (int i = 0; i < 8; ++i) {
        unsigned int v = 0;
        if (lane == 0) v = local_hash32[i];
        v = __shfl_sync(fullMask, v, 0);
        out32[i] = v;
    }
}
