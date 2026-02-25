#pragma once
#include <vector>
#include <string>

struct HashParams {
    std::vector<unsigned char> salt;
    int iterations;
    std::vector<unsigned char> iv;
    std::vector<unsigned char> encrypted_data;
};

std::vector<unsigned char> hex_to_bytes(const std::string& hex);
HashParams parse_hash(const std::string& hash);
