// Brute-force kernel CUDA implementation (minimal, safe, compile-ready)
#include "include/kernel.h"
#include "include/password_gen.h"
#include "crypto/pbkdf2.h"
#include "crypto/aes_ccm.h"
#include <cuda_runtime.h>
#include <cstdint>
#ifdef __has_include
# if __has_include(<nvToolsExt.h>)
#  include <nvToolsExt.h>
#  ifndef NVTX_EXT
#    define NVTX_EXT 1
#  endif
# endif
#endif

__global__ void brute_force_kernel(
    unsigned char* salt, int salt_len, int iterations,
    unsigned char* nonce, int nonce_len,
    unsigned char* encrypted_data, int encrypted_len,
    unsigned long long start_index, unsigned long long candidates_per_launch, int* found_flag,
    unsigned char* result_password,
    unsigned long long* region_cycles, unsigned long long* region_counts) {
    unsigned long long gid = static_cast<unsigned long long>(blockIdx.x) * blockDim.x + threadIdx.x;
    unsigned long long total_threads = static_cast<unsigned long long>(gridDim.x) * blockDim.x;

    // Each thread processes multiple candidates spaced by total_threads.
    for (unsigned long long offset = gid; offset < candidates_per_launch; offset += total_threads) {
        unsigned long long idx = start_index + offset;

        // quick check if another thread found the password
        if (*found_flag) return;

        // local buffer for ASCII recovery password (55 chars + NUL)
        unsigned char pwd[56];
        generate_password(idx, pwd);

        // derive key via PBKDF2-HMAC-SHA256 (32 bytes for AES-256)
        unsigned char key[32];
        size_t passlen = 0;
        while (passlen < 56 && pwd[passlen] != '\0') ++passlen;
        // NVTX range for external profilers (if available)
        #if defined(NVTX_EXT)
            nvtxRangePushA("PBKDF2");
        #endif
        unsigned long long t0 = clock64();
        pbkdf2_hmac_sha256_warp(pwd, passlen, salt, salt_len, iterations, key, 32);
        unsigned long long t1 = clock64();
        // accumulate cycles and counts for region 0 (PBKDF2)
        atomicAdd(&region_cycles[0], (unsigned long long)(t1 - t0));
        atomicAdd(&region_counts[0], 1ULL);
    #if defined(NVTX_EXT)
        nvtxRangePop();
    #endif

        // attempt AES-CCM decrypt of encrypted_data
        unsigned char plaintext[64]; // encrypted data in bitlocker is small (<=48)
    #if defined(NVTX_EXT)
        nvtxRangePushA("AES-CCM");
    #endif
        unsigned long long t2 = clock64();
        // key length = 32 (AES-256), tag length default 12
        bool ok = aes_ccm_decrypt(encrypted_data, encrypted_len, key, 32, nonce, nonce_len, 12, plaintext);
        unsigned long long t3 = clock64();
        atomicAdd(&region_cycles[1], (unsigned long long)(t3 - t2));
        atomicAdd(&region_counts[1], 1ULL);
    #if defined(NVTX_EXT)
        nvtxRangePop();
    #endif

        // verify VMK magic: 'V' 'M' 'K' 0x00
        if (plaintext[0] != 'V' || plaintext[1] != 'M' || plaintext[2] != 'K' || plaintext[3] != 0x00) continue;

        // Attempt to claim found_flag; only first claimer writes result
        int prev = atomicCAS(found_flag, 0, 1);
        if (prev == 0) {
            for (int i = 0; i < 56; ++i) result_password[i] = pwd[i];
        }
        return;
    }
}
