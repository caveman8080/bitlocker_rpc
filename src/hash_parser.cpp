// Hash parsing implementation
#include "include/hash_parser.h"
#include <vector>
#include <string>
#include <sstream>
#include <stdexcept>
#include <cctype>
#include <algorithm>

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

std::vector<unsigned char> hex_to_bytes(const std::string& hex) {
    std::vector<unsigned char> bytes;
    bytes.reserve((hex.size() + 1) / 2);
    std::string cleaned;
    cleaned.reserve(hex.size());
    for (char c : hex) {
        if (!std::isspace((unsigned char)c)) cleaned.push_back(c);
    }
    if (cleaned.size() % 2 != 0) throw std::invalid_argument("hex string has odd length");
    for (size_t i = 0; i < cleaned.size(); i += 2) {
        int hi = hexval(cleaned[i]);
        int lo = hexval(cleaned[i + 1]);
        if (hi < 0 || lo < 0) throw std::invalid_argument("invalid hex character");
        bytes.push_back(static_cast<unsigned char>((hi << 4) | lo));
    }
    return bytes;
}

HashParams parse_hash(const std::string& hash) {
    // Expected format (bitcracker/bitlocker):
    // bitlocker$version$saltLen$saltHex$iterations$ivLen$ivHex$encryptedLen$encryptedHex
    std::vector<std::string> parts;
    std::string token;
    std::istringstream ss(hash);
    while (std::getline(ss, token, '$')) parts.push_back(token);

    // Accept either "bitlocker$..." or "$bitlocker$..." (leading dollar)
    int offset = 0;
    if (parts.size() >= 10 && parts[0].empty() && parts[1] == "bitlocker") {
        offset = 1;
    }
    if ((int)parts.size() < 9 + offset) {
        throw std::invalid_argument("hash string has unexpected format; expected bitlocker$... fields");
    }
    if (parts[offset] != "bitlocker") {
        throw std::invalid_argument("unsupported hash prefix (expected 'bitlocker')");
    }

    // parse lengths and hex fields (indices shifted by offset if leading $ present)
    int saltLen = std::stoi(parts[2 + offset]);
    std::string saltHex = parts[3 + offset];
    int iterations = std::stoi(parts[4 + offset]);
    int ivLen = std::stoi(parts[5 + offset]);
    std::string ivHex = parts[6 + offset];
    int encryptedLen = std::stoi(parts[7 + offset]);
    std::string encryptedHex = parts[8 + offset];

    std::vector<unsigned char> salt = hex_to_bytes(saltHex);
    std::vector<unsigned char> iv = hex_to_bytes(ivHex);
    std::vector<unsigned char> encrypted = hex_to_bytes(encryptedHex);

    if ((int)salt.size() != saltLen) throw std::invalid_argument("salt length mismatch");
    if ((int)iv.size() != ivLen) throw std::invalid_argument("iv length mismatch");
    if ((int)encrypted.size() != encryptedLen) throw std::invalid_argument("encrypted data length mismatch");

    HashParams p;
    p.salt = std::move(salt);
    p.iterations = iterations;
    p.iv = std::move(iv);
    p.encrypted_data = std::move(encrypted);
    return p;
}