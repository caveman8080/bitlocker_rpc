#include "hash_parser.h"
#include <vector>
#include <string>
#include <stdexcept>

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
