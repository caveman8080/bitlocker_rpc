/**
 * @file password_gen.cu
 * @brief Device-side BitLocker recovery password generator (checksum-aware).
 *
 * Purpose: Maps flat 64-bit index -> canonical 48-digit password string (55 chars + NUL).
 * BitLocker format: 8 groups x 6 digits (000000-999999), sep '-', each group %11==0 (checksum trick).
 * Valid/group: floor(1000000/11)=90909 (0,11,22,...,999979).
 * Mask mode: Fixed groups from d_mask_fixed_vals[], unknowns from index %90909 *11.
 * Outputs ASCII buffer for PBKDF2 input.
 * Key Qs: "How does gen handle index overflow?", "Why 90909?", "Mask reduces to 90909^U".
 */

// Password generation CUDA implementation
#include "include/password_gen.h"

// Each 6-digit group must be a multiple of 11. There are 90909 possible values (0..90908).
// The full recovery password is 8 groups of 6 digits separated by '-' (48 digits + 7 hyphens = 55 chars).

// Device-side mask data (populated from host via cudaMemcpyToSymbol)
__device__ unsigned int d_mask_fixed_vals[8];
__device__ unsigned char d_mask_fixed_flags[8]; // 1 if fixed, 0 if unknown
__device__ int d_unknown_pos[8]; // positions of unknown groups (0..7)
__device__ int d_unknown_count = 0;

/**
 * @brief Generate valid BitLocker recovery password from index, respecting mask.
 * @param index Flat candidate index (0 -> first valid pwd).
 * @param password [out] 56-byte buffer: 48 digits +7 '-' + NUL.
 * Mask integration: Uses device symbols d_mask_fixed_* / d_unknown_pos/count.
 * Algo: idx into unknowns only: for each unknown group g: val = (idx % 90909)*11,
 *       unpack to 6 digits (pad 0), interleave fixed/mask vals + hyphens.
 * No overflow check (assumes host splits <ULLONG_MAX).
 * Called by every kernel thread for each stride candidate.
 */
__device__ void generate_password(unsigned long long index, unsigned char* password) {
    const int GROUPS = 8;
    const int PER_GROUP = 90909; // Multiples of 11: 0/11/.../999979 (1000000/11 floor)

    // Decompose index into unknown group values (LSB first for simplicity)
    unsigned int unknown_vals[8];
    unsigned long long idx = index;
    for (int i = (d_unknown_count - 1); i >= 0; --i) {
        unsigned int v = static_cast<unsigned int>(idx % PER_GROUP);
        unknown_vals[i] = v;
        idx /= PER_GROUP;
    }

    int out = 0;
    int uidx = 0;
    for (int g = 0; g < GROUPS; ++g) {
        unsigned int val6;
        if (d_mask_fixed_flags[g]) {
            val6 = d_mask_fixed_vals[g];
        } else {
            val6 = unknown_vals[uidx] * 11u;
            ++uidx;
        }
        // write 6 digits, zero-padded
        unsigned int v = val6;
        char buf[6];
        for (int d = 5; d >= 0; --d) {
            buf[d] = '0' + (v % 10u);
            v /= 10u;
        }
        for (int d = 0; d < 6; ++d) password[out++] = static_cast<unsigned char>(buf[d]);
        if (g != GROUPS - 1) password[out++] = '-';
    }
    password[out] = '\0';
}