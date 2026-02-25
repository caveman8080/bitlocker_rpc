#include "password_gen.h"

__device__ void generate_password(unsigned long long index, unsigned char* password) {
    const unsigned long long base = 90909ULL;
    const int pow10[] = {1, 10, 100, 1000, 10000, 100000};
    int pos = 0;
    for (int i = 0; i < 8; i++) {
        unsigned long long k = index % base;
        index /= base;
        int block_value = 11 * k;
        for (int j = 5; j >= 0; j--) {
            int digit = (block_value / pow10[j]) % 10;
            password[pos] = '0' + digit;
            password[pos + 1] = 0;
            pos += 2;
        }
        if (i < 7) {
            password[pos] = '-';
            password[pos + 1] = 0;
            pos += 2;
        }
    }
}
