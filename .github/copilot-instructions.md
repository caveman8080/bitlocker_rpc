# BitLocker RPC Copilot Instructions

## Project Overview
BitLocker Recovery Password Cracker (bitlocker_rpc) is a GPU-accelerated brute-force tool for recovering BitLocker recovery passwords using NVIDIA CUDA. It parses bitcracker hashes, generates candidate passwords, derives keys, decrypts, and verifies results—all on the GPU.

## Architecture & Key Components
- **Main Pipeline:**
  - Hash parsing (`parse_hash`): Extracts salt, iterations, IV, encrypted data from bitcracker hash
  - Password generation (`generate_password`): Maps index to BitLocker recovery password (8 blocks, 6 digits each, separated by dashes)
  - Key derivation (`recovery_password_to_key`): PBKDF2-HMAC-SHA256
  - Decryption (`aes_ccm_decrypt`): AES-256-CCM
  - Verification (`verify_decrypted`): Checks for 'VMK' magic bytes
- **GPU Kernel:**
  - `brute_force_kernel`: Tests candidates in parallel, signals found password via `atomicCAS`
  - All cryptographic routines (SHA-256, HMAC, PBKDF2, AES, CCM) are implemented as device code
- **Password Space:**
  - 8 blocks, each block: 6 digits, generated as `11 * k` (k ∈ [0, 90908])
  - Total candidates: $90909^8$

## Build & Run Workflow
- **Build:**
  - Find GPU compute capability: `nvidia-smi`
  - Compile: `nvcc -gencode arch=compute_XX,code=sm_XX -v -o bitlocker_rpc bitlocker_rpc.cu`
- **Run:**
  - `./bitlocker_rpc 'HASH_STRING'` (hash as argument)
  - `./bitlocker_rpc -f hash.txt` (hash from file)
  - `./bitlocker_rpc -f hash.txt -t 512 -b 512` (custom thread/block config)
  - `./bitlocker_rpc -f hash.txt -o out.txt` (output to file)

## Project-Specific Patterns & Constraints
- **CUDA_CHECK macro:** All CUDA API calls are wrapped for error handling
- **Fixed buffer sizes:** Password (110 bytes), ciphertext (48 bytes), no dynamic allocation in kernels
- **Hash format:** `bitlocker$version$saltLen$saltHex$iterations$ivLen$ivHex$encryptedLen$encryptedHex`
- **Data validation:** Salt/IV/encrypted lengths must match hex string byte count; IV must be 12 bytes; decrypted VMK: 'V', 'M', 'K', 0x00
- **Progress reporting:** Separate threads for candidate count and GPU utilization (calls `nvidia-smi`)
- **Single GPU only:** No multi-GPU support; would require new CUDA stream management

## Debugging & Testing
- **Windows notes:** Use `nvidia-smi.exe` or ensure PATH; hash files must use LF line endings
- **Debug checklist:**
  - Hash parsing: check `hex_to_bytes` conversion
  - Candidate count: verify `max_index` and `candidates_per_launch`
  - Found flag: check `aes_ccm_decrypt` and `TAG_LEN=12`
  - GPU memory: verify `cudaMalloc` sizes
  - Kernel failures: always wrap with `CUDA_CHECK`

## Common Modifications
- Add new crypto: implement new `__device__` functions, call from kernel
- Change password space: update `generate_password` and `max_index`
- Log found candidates: modify verification check before atomic flag

## Key Files & References
- [src/bitlocker_rpc.cu](../src/bitlocker_rpc.cu): Main implementation
- [README.md](../README.md): Build/run instructions
- [crypto/](../crypto/): Device crypto routines

---
**Feedback needed:** If any section is unclear, incomplete, or missing important project-specific knowledge, please specify so it can be improved for future AI agents.
