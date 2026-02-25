#include "common.h"
#include "hash_parser.h"
#include "password_gen.h"
#include "crypto/sha256.h"
#include "crypto/hmac_sha256.h"
#include "crypto/pbkdf2.h"
#include "crypto/aes256.h"
#include "crypto/aes_ccm.h"
#include "kernel.h"
#include "utils.h"
#include <getopt.h>
#include <fstream>
#include <iostream>
#include <string>
#include <sstream>

// ...existing code...
    return (TS0[b] >> 16) & 0xFF;
}

__device__ void shift_rows(unsigned char *state) {
    unsigned char t;
    t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
    t = state[2]; state[2] = state[10]; state[10] = t; t = state[6]; state[6] = state[14]; state[14] = t;
    t = state[3]; state[3] = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = t;
}

__device__ void aes256_key_expansion(const unsigned char *key, unsigned char *w) {
    unsigned int *ww = (unsigned int *)w;
    for (int i = 0; i < 8; i++) ww[i] = ((unsigned int *)key)[i];
    for (int i = 8; i < 60; i++) {
        unsigned int temp = ww[i - 1];
        if (i % 8 == 0) {
            temp = (temp << 8) | (temp >> 24);
            temp = get_sbox(temp) | (get_sbox(temp >> 8) << 8) | (get_sbox(temp >> 16) << 16) | (get_sbox(temp >> 24) << 24);
            temp ^= rcon[i / 8];
        } else if (i % 8 == 4) {
            temp = get_sbox(temp) | (get_sbox(temp >> 8) << 8) | (get_sbox(temp >> 16) << 16) | (get_sbox(temp >> 24) << 24);
        }
        ww[i] = ww[i - 8] ^ temp;
    }
}

__device__ void add_round_key(unsigned char* state, const unsigned char* round_key) {
    for (int i = 0; i < 16; i++) {
        state[i] ^= round_key[i];
    }
}

__device__ void aes_encrypt_block(const unsigned char *in, unsigned char *out, const unsigned char *key) {
    unsigned char state[16];
    memcpy(state, in, 16);
    unsigned char rk[240];
    aes256_key_expansion(key, rk);
    add_round_key(state, rk);
    for (int r = 1; r < 14; r++) {
        unsigned int t0 = TS0[state[0]] ^ TS1[state[5]] ^ TS2[state[10]] ^ TS3[state[15]] ^ ((unsigned int *)rk)[r * 4];
        unsigned int t1 = TS0[state[1]] ^ TS1[state[6]] ^ TS2[state[11]] ^ TS3[state[12]] ^ ((unsigned int *)rk)[r * 4 + 1];
        unsigned int t2 = TS0[state[2]] ^ TS1[state[7]] ^ TS2[state[8]] ^ TS3[state[13]] ^ ((unsigned int *)rk)[r * 4 + 2];
        unsigned int t3 = TS0[state[3]] ^ TS1[state[4]] ^ TS2[state[9]] ^ TS3[state[14]] ^ ((unsigned int *)rk)[r * 4 + 3];
        *(unsigned int *)(state + 0) = t0;
        *(unsigned int *)(state + 4) = t1;
        *(unsigned int *)(state + 8) = t2;
        *(unsigned int *)(state + 12) = t3;
    }
    for (int i = 0; i < 16; i++) state[i] = get_sbox(state[i]);
    shift_rows(state);
    add_round_key(state, rk + 224);
    memcpy(out, state, 16);
}

__device__ void sha256_init(uint32_t *h) {
    h[0] = 0x6a09e667; h[1] = 0xbb67ae85; h[2] = 0x3c6ef372; h[3] = 0xa54ff53a;
    h[4] = 0x510e527f; h[5] = 0x9b05688c; h[6] = 0x1f83d9ab; h[7] = 0x5be0cd19;
}

__device__ void sha256_transform(const unsigned char *data, uint32_t *h) {
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

__device__ void hmac_sha256(const unsigned char *key, size_t keylen, const unsigned char *msg, size_t msglen, unsigned char *out) {
    unsigned char kpad[64];
    memset(kpad, 0, 64);
    if (keylen > 64) {
        sha256(key, keylen, kpad);
    } else {
        memcpy(kpad, key, keylen);
    }
    unsigned char inner[64 + 1024];
    for (int i = 0; i < 64; i++) inner[i] = kpad[i] ^ 0x36;
    memcpy(inner + 64, msg, msglen);
    unsigned char temp[32];
    sha256(inner, 64 + msglen, temp);
    unsigned char outer[64 + 32];
    for (int i = 0; i < 64; i++) outer[i] = kpad[i] ^ 0x5c;
    memcpy(outer + 64, temp, 32);
    sha256(outer, 64 + 32, out);
}

__device__ void pbkdf2_hmac_sha256(const unsigned char *pass, size_t passlen, const unsigned char *salt, size_t saltlen, int iterations, unsigned char *dk, size_t dklen) {
    unsigned char tmp[32];
    unsigned char buf[64 + 4];
    memcpy(buf, salt, saltlen);
    int block = 1;
    size_t off = 0;
    while (off < dklen) {
        buf[saltlen] = block >> 24; buf[saltlen + 1] = block >> 16;
        buf[saltlen + 2] = block >> 8; buf[saltlen + 3] = block;
        hmac_sha256(pass, passlen, buf, saltlen + 4, tmp);
        unsigned char u[32];
        memcpy(u, tmp, 32);
        for (int i = 1; i < iterations; i++) {
            hmac_sha256(pass, passlen, u, 32, u);
            for (int j = 0; j < 32; j++) tmp[j] ^= u[j];
        }
        size_t cp = (dklen - off > 32) ? 32 : dklen - off;
        memcpy(dk + off, tmp, cp);
        off += cp;
        block++;
    }
}

__device__ bool aes_ccm_decrypt(const unsigned char *encrypted, int encrypted_len, const unsigned char *key, const unsigned char *nonce, int nonce_len, unsigned char *decrypted) {
    const int TAG_LEN = 12;
    const int AES_BLOCK_SIZE = 16;
    int ciphertext_len = encrypted_len - TAG_LEN;
    if (ciphertext_len <= 0 || nonce_len != 12) return false;
    int L = 15 - nonce_len;
    unsigned char ciphertext[48];
    unsigned char tag[12];
    memcpy(ciphertext, encrypted, ciphertext_len);
    memcpy(tag, encrypted + ciphertext_len, TAG_LEN);
    unsigned char counter[16];
    counter[0] = L - 1;
    memcpy(counter + 1, nonce, nonce_len);
    memset(counter + 1 + nonce_len, 0, L);
    unsigned char key_stream_block[16];
    int ctr = 1;
    for (int i = 0; i < ciphertext_len; i += AES_BLOCK_SIZE) {
        unsigned char ctr_counter[16];
        memcpy(ctr_counter, counter, 16);
        uint32_t c_val = ctr;
        for (int j = L - 1; j >= 0; j--) {
            ctr_counter[15 - j] = c_val & 0xFF;
            c_val >>= 8;
        }
        aes_encrypt_block(ctr_counter, key_stream_block, key);
        int cp = (AES_BLOCK_SIZE < ciphertext_len - i ? AES_BLOCK_SIZE : ciphertext_len - i);
        for (int j = 0; j < cp; j++) {
            decrypted[i + j] = ciphertext[i + j] ^ key_stream_block[j];
        }
        ctr++;
    }
    int flags = ((TAG_LEN - 2) / 2 << 3) | (L - 1);
    unsigned char B0[16];
    B0[0] = flags;
    memcpy(B0 + 1, nonce, nonce_len);
    uint32_t m_len = ciphertext_len;
    for (int j = L - 1; j >= 0; j--) {
        B0[15 - j] = m_len & 0xFF;
        m_len >>= 8;
    }
    unsigned char mac[16];
    aes_encrypt_block(B0, mac, key);
    for (int i = 0; i < ciphertext_len; i += AES_BLOCK_SIZE) {
        unsigned char block[16] = {0};
        int cp = (AES_BLOCK_SIZE < ciphertext_len - i ? AES_BLOCK_SIZE : ciphertext_len - i);
        memcpy(block, decrypted + i, cp);
        for (int j = 0; j < AES_BLOCK_SIZE; j++) block[j] ^= mac[j];
        aes_encrypt_block(block, mac, key);
    }
    unsigned char counter0[16];
    counter0[0] = L - 1;
    memcpy(counter0 + 1, nonce, nonce_len);
    memset(counter0 + 1 + nonce_len, 0, L);
    unsigned char S0[16];
    aes_encrypt_block(counter0, S0, key);
    for (int i = 0; i < TAG_LEN; i++) {
        if ((S0[i] ^ mac[i]) != tag[i]) return false;
    }
    return true;
}

__device__ bool verify_decrypted(const unsigned char* decrypted, size_t len) {
    if (len < 4) return false;
    return (decrypted[0] == 'V' && decrypted[1] == 'M' && decrypted[2] == 'K' && decrypted[3] == 0);
}

__device__ void recovery_password_to_key(const unsigned char *password, const unsigned char *salt, int salt_len, int iterations, unsigned char *key) {
    pbkdf2_hmac_sha256(password, 110, salt, salt_len, iterations, key, 32);
}

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

__global__ void brute_force_kernel(
    unsigned char* salt, int salt_len, int iterations,
    unsigned char* nonce, int nonce_len,
    unsigned char* encrypted_data, int encrypted_len,
    unsigned long long start_index, int* found_flag,
    unsigned char* result_password) {

    unsigned long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned long long index = start_index + tid;

    unsigned char password[110];
    generate_password(index, password);

    unsigned char derived_key[32];
    recovery_password_to_key(password, salt, salt_len, iterations, derived_key);

    unsigned char decrypted[48];
    bool success = aes_ccm_decrypt(encrypted_data, encrypted_len, derived_key, nonce, nonce_len, decrypted);
    if (success && verify_decrypted(decrypted, 48)) {
        if (atomicCAS(found_flag, 0, 1) == 0) {
            memcpy(result_password, password, 110);
        }
    }
}

struct HashParams {
    std::vector<unsigned char> salt;
    int iterations;
    std::vector<unsigned char> iv;
    std::vector<unsigned char> encrypted_data;
};

std::vector<unsigned char> hex_to_bytes(const std::string& hex) {
    std::vector<unsigned char> bytes;
    if (hex.length() % 2 != 0) {
        throw std::runtime_error("Hex string length must be even");
    }
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byte_str = hex.substr(i, 2);
        unsigned char byte = static_cast<unsigned char>(std::stoi(byte_str, nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

HashParams parse_hash(const std::string& hash) {
    HashParams params;
    std::vector<std::string> fields;
    std::stringstream ss(hash);
    std::string field;
    while (std::getline(ss, field, '$')) {
        if (!field.empty()) {
            fields.push_back(field);
        }
    }
    if (fields.size() < 9 || fields[0] != "bitlocker") {
        throw std::runtime_error("Invalid BitLocker hash format");
    }
    try {
        size_t idx = 1;
        idx++;
        int salt_len = std::stoi(fields[idx++]);
        std::string salt_hex = fields[idx++];
        if (salt_hex.length() != static_cast<size_t>(salt_len) * 2) {
            throw std::runtime_error("Salt length mismatch");
        }
        params.salt = hex_to_bytes(salt_hex);
        params.iterations = std::stoi(fields[idx++]);
        int iv_len = std::stoi(fields[idx++]);
        std::string iv_hex = fields[idx++];
        if (iv_hex.length() != static_cast<size_t>(iv_len) * 2) {
            throw std::runtime_error("IV length mismatch");
        }
        params.iv = hex_to_bytes(iv_hex);
        int encrypted_len = std::stoi(fields[idx++]);
        std::string encrypted_hex = fields[idx++];
        if (encrypted_hex.length() != static_cast<size_t>(encrypted_len) * 2) {
            throw std::runtime_error("Encrypted data length mismatch");
        }
        params.encrypted_data = hex_to_bytes(encrypted_hex);
    } catch (const std::exception& e) {
        throw std::runtime_error("Failed to parse hash: " + std::string(e.what()));
    }
    return params;
}

bool running = true;
unsigned long long total_candidates_tested = 0;

void display_progress() {
    while (running) {
        std::cout << "Total candidates tested: " << total_candidates_tested << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(10));
    }
}

void display_gpu_utilization() {
    while (running) {
        std::cout << "GPU Utilization: ";
		system("nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits  ");
        std::this_thread::sleep_for(std::chrono::seconds(10));
    }
}

int main(int argc, char* argv[]) {
    std::string hash_str;
    std::string input_file;
    std::string output_file = "found.txt";
    int threads_per_block = 256;
    int blocks = 256;

    int opt;
    while ((opt = getopt(argc, argv, "hf:t:b:o:")) != -1) {
        switch (opt) {
            case 'h':
                std::cout << "Usage: " << argv[0] << " [options] [hash]" << std::endl;
                std::cout << "Options:" << std::endl;
                std::cout << "  -h        Show this help message and exit." << std::endl;
                std::cout << "  -f <file> Input file containing the BitLocker hash." << std::endl;
                std::cout << "  -t <num>  Set the number of threads per block (default: 256)." << std::endl;
                std::cout << "  -b <num>  Set the number of blocks (default: 256)." << std::endl;
                std::cout << "  -o <file> Output the found recovery key to the specified file (default: found.txt in current directory)." << std::endl;
                return 0;
            case 'f':
                input_file = optarg;
                break;
            case 't':
                threads_per_block = std::atoi(optarg);
                break;
            case 'b':
                blocks = std::atoi(optarg);
                break;
            case 'o':
                output_file = optarg;
                break;
            default:
                std::cerr << "Unknown option: -" << char(optopt) << std::endl;
                return 1;
        }
    }

    if (!input_file.empty()) {
        std::ifstream ifs(input_file);
        if (!ifs) {
            std::cerr << "Error opening input file: " << input_file << std::endl;
            return 1;
        }
        std::stringstream ss;
        ss << ifs.rdbuf();
        hash_str = ss.str();
        // Trim trailing newline if present
        if (!hash_str.empty() && hash_str.back() == '\n') {
            hash_str.pop_back();
        }
    } else if (optind < argc) {
        hash_str = argv[optind];
    } else {
        std::cerr << "No hash provided. Use -h for help." << std::endl;
        return 1;
    }

    try {
        HashParams params = parse_hash(hash_str);

        unsigned char *d_salt, *d_nonce, *d_encrypted, *d_result_password;
        int *d_found_flag;
        CUDA_CHECK(cudaMalloc(&d_salt, params.salt.size()));
        CUDA_CHECK(cudaMalloc(&d_nonce, params.iv.size()));
        CUDA_CHECK(cudaMalloc(&d_encrypted, params.encrypted_data.size()));
        CUDA_CHECK(cudaMalloc(&d_found_flag, sizeof(int)));
        CUDA_CHECK(cudaMalloc(&d_result_password, 110));

        CUDA_CHECK(cudaMemcpy(d_salt, params.salt.data(), params.salt.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_nonce, params.iv.data(), params.iv.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_encrypted, params.encrypted_data.data(), params.encrypted_data.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemset(d_found_flag, 0, sizeof(int)));

        unsigned long long candidates_per_launch = static_cast<unsigned long long>(blocks) * threads_per_block;

        std::thread progress_thread(display_progress);
        std::thread gpu_thread(display_gpu_utilization);

        unsigned long long max_index = 1ULL;
        for (int i = 0; i < 8; i++) max_index *= 90909ULL;

        for (unsigned long long start = 0; start < max_index; start += candidates_per_launch) {
            brute_force_kernel<<<blocks, threads_perblock>>>(
                d_salt, params.salt.size(), params.iterations,
                d_nonce, params.iv.size(),
                d_encrypted, params.encrypted_data.size(),
                start, d_found_flag, d_result_password
            );
            cudaDeviceSynchronize();

            total_candidates_tested += candidates_per_launch;

            int found;
            CUDA_CHECK(cudaMemcpy(&found, d_found_flag, sizeof(int), cudaMemcpyDeviceToHost));
            if (found) {
                unsigned char result[110];
                CUDA_CHECK(cudaMemcpy(result, d_result_password, 110, cudaMemcpyDeviceToHost));
                std::ofstream ofs(output_file);
                if (!ofs) {
                    std::cerr << "Error opening output file: " << output_file << std::endl;
                    break;
                }
                ofs << "Password found: ";
                for (int i = 0; i < 110; i += 2) {
                    ofs << result[i];
                }
                ofs << std::endl;
                std::cout << "Password found and written to " << output_file << std::endl;
                break;
            }
        }

        running = false;
        progress_thread.join();
        gpu_thread.join();

        cudaFree(d_salt);
        cudaFree(d_nonce);
        cudaFree(d_encrypted);
        cudaFree(d_found_flag);
        cudaFree(d_result_password);
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
