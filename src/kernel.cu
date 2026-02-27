/**
 * @file kernel.cu
 * @brief Core brute-force kernel: password gen + PBKDF2 + AES-CCM VMK verify.
 *
 * Purpose: Massive parallel test of candidate indices against hash params.
 * Thread model: grid(blocks) x block(threads), global ID stride over candidates_per_launch.
 * Early abort: atomic read found_flag before each candidate.
 * Crypto chain:
 *   1. gen pwd -> PBKDF2(pass,salt,100k)->VMK_key(32B)
 *   2. AES-CCM decrypt(enc_data,key=VMK,nonce=IV,tag=12B)->plaintext
 *   3. Check plaintext starts "VMK\0" (magic for valid VMK protector).
 * Claim: atomicCAS(found_flag,0,1) -> copy pwd to result.
 * Profiling: Optional clock64 regions (PBKDF2/AES) for host stats (64b atomic).
 * Qs: "Why VMK\0?", "Stride indexing?", "Constant-time?" (no, but GPU safe).
 */

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

/**
 * @brief Brute-force kernel: test range of password indices against BitLocker hash.
 * @param salt/iv/enc_data Host-uploaded hash components (async memcpy).
 * @param iterations Typically 100,000 for PBKDF2.
 * @param start_index/candidates_per_launch Per-launch chunk (strided by threads).
 * @param found_flag [global atomic] 0->busy, set 1 by finder (read before each cand).
 * @param result_password [global] Winning pwd copied by CAS claimer only.
 * @param region_* Optional profiling: cycles/counts for PBKDF2(0)/AES(1).
 * Exits early on found_flag!=0 (cooperative abort).
 * Memory: Local pwd[56], key[32], pt[64]; no shared (scalable).
 * Perf: Warp-sync PBKDF2, CCM optimized for small data.
 */
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

        // quick check if another thread found the password (atomic read)
        if (atomicAdd(found_flag, 0) != 0) return;

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
    #if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 600)
        atomicAdd(&region_cycles[0], (unsigned long long)(t1 - t0));
        atomicAdd(&region_counts[0], 1ULL);
    #else
        // Device does not guarantee 64-bit atomicAdd; skip profiling on older archs.
    #endif
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
        if (!ok) continue;
        unsigned long long t3 = clock64();
    #if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 600)
        atomicAdd(&region_cycles[1], (unsigned long long)(t3 - t2));
        atomicAdd(&region_counts[1], 1ULL);
    #else
        // Skip 64-bit profiling updates on older architectures.
    #endif
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
