// AES-128 CUDA implementation (compact reference-style)
#include "aes128.h"
#include "aes256.h" // reuse sbox etc.
#include <cstring>

// forward declarations for helpers implemented in aes256.cu
extern __device__ void sub_bytes(unsigned char *state);
extern __device__ void mix_columns(unsigned char *s);
extern __device__ unsigned char xtime(unsigned char x);

__device__ void aes128_key_expansion(const unsigned char *key, unsigned char *w) {
    // key: 16 bytes, w: 176 bytes (11 round keys * 16)
    const unsigned char Rcon[11] = {0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36};
    // first 16 bytes are the key
    memcpy(w, key, 16);
    int bytes_generated = 16;
    int rcon_iter = 1;
    unsigned char temp[4];
    while (bytes_generated < 176) {
        for (int i = 0; i < 4; ++i) temp[i] = w[bytes_generated - 4 + i];
        if (bytes_generated % 16 == 0) {
            unsigned char t = temp[0]; temp[0]=temp[1]; temp[1]=temp[2]; temp[2]=temp[3]; temp[3]=t;
            temp[0] = get_sbox(temp[0]); temp[1] = get_sbox(temp[1]); temp[2] = get_sbox(temp[2]); temp[3] = get_sbox(temp[3]);
            temp[0] ^= Rcon[rcon_iter++];
        }
        for (int i = 0; i < 4; ++i) {
            w[bytes_generated] = (unsigned char)(w[bytes_generated - 16] ^ temp[i]);
            bytes_generated++;
        }
    }
}

__device__ void aes128_encrypt_block(const unsigned char *in, unsigned char *out, const unsigned char *key) {
    unsigned char state[16];
    unsigned char round_keys[176];
    memcpy(state, in, 16);
    aes128_key_expansion(key, round_keys);
    add_round_key(state, round_keys); // round 0
    for (int round = 1; round <= 9; ++round) {
        sub_bytes(state);
        shift_rows(state);
        mix_columns(state);
        add_round_key(state, round_keys + round*16);
    }
    // final round
    sub_bytes(state);
    shift_rows(state);
    add_round_key(state, round_keys + 10*16);
    memcpy(out, state, 16);
}
