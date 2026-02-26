// Password generation CUDA implementation
#include "include/password_gen.h"

// Each 6-digit group must be a multiple of 11. There are 90909 possible values (0..90908).
// The full recovery password is 8 groups of 6 digits separated by '-' (48 digits + 7 hyphens = 55 chars).

__device__ void generate_password(unsigned long long index, unsigned char* password) {
    const int GROUPS = 8;
    const int PER_GROUP = 90909; // number of valid 6-digit values divisible by 11 (0..999999 -> floor(999999/11)+1)
    unsigned int groups[GROUPS];
    unsigned long long idx = index;
    for (int i = GROUPS - 1; i >= 0; --i) {
        groups[i] = static_cast<unsigned int>(idx % PER_GROUP);
        idx /= PER_GROUP;
    }

    int out = 0;
    for (int g = 0; g < GROUPS; ++g) {
        unsigned int val = groups[g] * 11u; // actual 6-digit value
        // write 6 digits, zero-padded
        char buf[6];
        for (int d = 5; d >= 0; --d) {
            buf[d] = '0' + (val % 10u);
            val /= 10u;
        }
        for (int d = 0; d < 6; ++d) password[out++] = static_cast<unsigned char>(buf[d]);
        if (g != GROUPS - 1) password[out++] = '-';
    }
    password[out] = '\0';
}