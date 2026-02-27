// Password generation CUDA implementation
#include "include/password_gen.h"

// Each 6-digit group must be a multiple of 11. There are 90909 possible values (0..90908).
// The full recovery password is 8 groups of 6 digits separated by '-' (48 digits + 7 hyphens = 55 chars).

// Device-side mask data (populated from host via cudaMemcpyToSymbol)
__device__ unsigned int d_mask_fixed_vals[8];
__device__ unsigned char d_mask_fixed_flags[8]; // 1 if fixed, 0 if unknown
__device__ int d_unknown_pos[8]; // positions of unknown groups (0..7)
__device__ int d_unknown_count = 0;

__device__ void generate_password(unsigned long long index, unsigned char* password) {
    const int GROUPS = 8;
    const int PER_GROUP = 90909; // number of valid 6-digit values divisible by 11

    // Map index into unknown groups only
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