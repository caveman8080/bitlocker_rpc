# BitLocker RPC Copilot Instructions

## Project Overview
BitLocker Recovery Password Cracker (RPC) is a GPU-accelerated brute-force tool that attempts to recover BitLocker recovery passwords using NVIDIA CUDA. The tool uses OpenSSL's bitcracker to extract hash parameters, then leverages GPU parallelism to test candidate passwords.

## Architecture & Key Components

### Core Algorithm Pipeline
1. **Hash Parsing** (`parse_hash()` in main): Extracts salt, iteration count, nonce (IV), and encrypted data from bitcracker-formatted hash
2. **Password Generation** (`generate_password()` kernel): Maps indices (0 to 90909^8) to valid BitLocker recovery passwords using 8 blocks of 12 digits (format: XXXXXX-XXXXXX-...-XXXXXX)
3. **Key Derivation** (`recovery_password_to_key()` kernel): Uses PBKDF2-HMAC-SHA256 with extracted salt/iterations
4. **Decryption** (`aes_ccm_decrypt()` kernel): AES-256-CCM decryption of password-protected data
5. **Verification** (`verify_decrypted()` kernel): Checks for "VMK" magic bytes in decrypted data

### GPU Kernel Strategy
- **Single kernel launch per batch**: `brute_force_kernel()` tests `blocks * threads_per_block` candidate passwords in parallel
- **Atomic operations**: Uses `atomicCAS()` to safely signal password discovery across threads
- **Search iteration**: Main loop increments start_index by candidates_per_launch until all ~10^38 candidates exhausted or password found

### Cryptographic Implementations (Device Code)
- **SHA-256**: Complete implementation in `sha256()`, called by HMAC and PBKDF2
- **HMAC-SHA256**: Implements outer/inner padding (0x5c/0x36) in `hmac_sha256()`
- **PBKDF2**: Block counter in `pbkdf2_hmac_sha256()` ensures full key material generation
- **AES-256**: Uses precomputed S-box and T-tables (TS0-TS3) for encryption; key expansion via `aes256_key_expansion()`
- **AES-CCM Mode**: Counter mode streaming decryption + CBC-MAC authentication verification

## Build & Runtime

### Compilation
```bash
# Find your GPU compute capability:
nvidia-smi

# Build (replace XX with compute capability, e.g., compute_75 for RTX 2080):
nvcc -gencode arch=compute_XX,code=sm_XX -v -o bitlocker_rpc bitlocker_rpc.cu
```

### Execution
```bash
./bitlocker_rpc 'HASH_STRING'          # Hash as argument
./bitlocker_rpc -f hash.txt            # Hash from file
./bitlocker_rpc -f hash.txt -t 512 -b 512  # Custom thread/block config
./bitlocker_rpc -f hash.txt -o out.txt # Write result to file
```

## Important Constraints & Patterns

### GPU Memory Management
- **CUDA_CHECK macro**: All GPU API calls wrapped to catch memory allocation/sync errors
- **Fixed buffer sizes**: Precomputed for specific data types (e.g., 48-byte ciphertext, 110-byte password)
- **No dynamic allocation in kernels**: Stack-based buffers only

### Password Index Mapping
- Range: 0 to 90909^8 - 1 (each of 8 blocks maps 0-90908 via `index % 90909`)
- 6 decimal digits per block generated as: `11 * k` where k ∈ [0, 90908]
- This maps to valid BitLocker format (6 digits per block, dashes between)

### Hash Format (bitcracker output)
```
bitlocker$version$saltLen$saltHex$iterations$ivLen$ivHex$encryptedLen$encryptedHex
```

### Data Validation
- Salt/IV/encrypted lengths must match hex string byte count
- Minimum ciphertext: 16 bytes (one AES block)
- IV (nonce) must be exactly 12 bytes
- Decrypted VMK validated by checking first 4 bytes: 'V', 'M', 'K', 0x00

## Performance Tuning

### Thread Block Configuration
- Default: 256 threads/block, 256 blocks (65,536 parallel tests per launch)
- Adjust `-t` and `-b` based on GPU:
  - High-end (RTX 3090): `-t 1024 -b 512` may improve throughput
  - Consumer GPU (GTX 1080): stick with `-t 256 -b 256`
- More blocks = more iterations but diminishing returns after saturation

### Batch Size Calculation
- `candidates_per_launch = blocks * threads_per_block`
- `CUDA kernel latency ~1-10ms`, so minimize launches for long searches
- Progress reporting threads (display_progress, display_gpu_utilization) run in parallel with GPU

## Common Modifications

- **Adding new crypto**: Implement new `__device__` functions; call from kernel
- **Changing password space**: Modify `generate_password()` block count/range; update `max_index` calculation
- **Logging found candidates**: Modify verification check to log before atomic flag
- **Multi-GPU support**: Currently single GPU only; would require different CUDA stream management

## Testing & Debugging

### Windows-Specific Notes
- Use `nvidia-smi.exe` (full path) or rely on PATH setup for nvidia-smi
- Output file suppression: no direct equivalent to `/dev/null`; use a temporary file or ignore output
- Hash files should use Unix-style line endings (LF) to avoid parsing issues

### General Debugging Checklist
- **Hash parsing fails**: Add `std::cerr` output in `parse_hash()` to verify `hex_to_bytes()` correctly converts salt/IV/encrypted data
- **No candidates tested**: Verify `max_index` calculation (should be ~10^38) and `candidates_per_launch > 0`
- **Found flag never sets**: Confirm `aes_ccm_decrypt()` returns true for the correct password; check `TAG_LEN=12` matches encrypted data structure
- **GPU memory errors**: Verify all `cudaMalloc` sizes match actual data lengths (salt, IV, encrypted_data)
- **Silent kernel failures**: CUDA errors may not propagate; always wrap GPU calls with `CUDA_CHECK` macro

## Key Files
- [bitlocker_rpc.cu](./bitlocker_rpc.cu): Complete implementation (~661 lines)
- [README.md](./README.md): Basic build/run instructions
