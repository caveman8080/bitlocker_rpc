![GPU Accelerated](https://img.shields.io/badge/GPU-CUDA-green)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://opensource.org/licenses/GPL-3.0)

# BitLocker Recovery Password Cracker (bitlocker_rpc)

One-line: GPU-accelerated BitLocker recovery-password tester for lawful, authorized recovery of your own drives.

## Table of Contents
- Features
Hash Extraction Guidance (Bitcracker)
Legal & Ethical Disclaimer
How BitLocker Recovery Passwords Work (brief)
Hardware & Software Requirements
Build Instructions (repo-native)
Usage
Performance Notes
Roadmap & Limitations
Contributing & License

## Features
- GPU-accelerated candidate testing using CUDA (`nvcc`)
- Supports the bitcracker-style `$bitlocker$...` hash format
- Configurable threads/blocks for tuning on different GPUs
- Device-side crypto primitives (AES-CCM, PBKDF2-HMAC-SHA256) implemented for high throughput
- Unit tests for AES-CCM (RFC vectors + randomized tests)

## Legal & Ethical Disclaimer (READ CAREFULLY)
- This tool is intended strictly for legitimate, authorized recovery of BitLocker recovery passwords on drives you own or are explicitly authorized to recover. Unauthorized use to access or attempt to access systems or data you do not own or have permission to test is illegal and unethical.
- By using this project you agree to comply with all applicable laws and institutional policies. The authors and maintainers disclaim liability for any misuse.
- If you are performing security research or responsible disclosure, follow the `SECURITY.md` policy in this repository and contact maintainers responsibly.

## How BitLocker Recovery Passwords Work (brief)
- BitLocker recovery passwords are commonly 48-digit numeric values formatted as 8 groups of 6 digits. Each 6-digit block includes a checksum digit in common implementations. This repository implements mapping from candidate numeric passwords to the derived keys used by BitLocker and tests those candidates on the GPU.

## Hardware & Software Requirements
- NVIDIA GPU with CUDA support and an appropriate CUDA Toolkit installed.
- `nvcc` (CUDA compiler) and a C++ compiler supported by CUDA on Windows (MSVC) or Linux (gcc).
- Build scripts are provided for convenience: `scripts/build.bat` (Windows) and `scripts/build.sh` (Unix-like) if present.
- Sufficient GPU memory and a compatible driver for running high-throughput brute-force workloads.

## Build Instructions (repo-native)
This repository provides platform-specific build scripts; it does not include a CMake configuration by default. Use the provided scripts or a manual `nvcc` invocation as shown below.

Windows (recommended):
```powershell
cd <repo-root>
scripts\build.bat
# Output: build\bitlocker_rpc.exe and test binaries under build\
# The build script will automatically detect your GPU's compute capability (SM version) using nvidia-smi.
# If detection fails, it defaults to SM 75. You can override by setting the SM environment variable:
#   set SM=89
```

Linux/Unix (recommended):
```bash
cd <repo-root>
scripts/build.sh
# Output: build/bitlocker_rpc and test binaries under build/
# The build script will automatically detect your GPU's compute capability (SM version) using nvidia-smi.
# If detection fails, it defaults to SM 75. You can override by setting the SM environment variable:
#   export SM=89
```

Manual nvcc example (Linux/macOS or custom invocation):
```bash
nvcc -gencode arch=compute_75,code=sm_75 -I src -I src/include -rdc=true -O3 \
  -o build/bitlocker_rpc \
  src/bitlocker_rpc.cu src/hash_parser.cpp src/kernel.cu src/password_gen.cu src/utils.cpp \
  src/crypto/aes_ccm.cu src/crypto/aes128.cu src/crypto/aes256.cu
```

## Usage
- Show help (smoke test):
```bash
build/bitlocker_rpc.exe -h
```
```bash
build/bitlocker_rpc.exe "bitlocker$..."
```
build/bitlocker_rpc.exe "bitlocker$..."
```bash
```
## Hash Extraction Guidance (Bitcracker)

To extract a BitLocker hash from a drive for use with this tool, we recommend the Bitcracker HashExtractor utility:

- [Bitcracker HashExtractor on GitHub](https://github.com/e-ago/bitcracker/tree/master/src_HashExtractor)

Bitcracker is an open-source project that provides tools for extracting BitLocker hashes from Windows volumes. Please credit the Bitcracker authors for their work on hash extraction and refer to their documentation for detailed instructions.

This project accepts hashes in the Bitcracker format (starting with `bitlocker$` or `$bitlocker$`).

### Hash format
- Expected format (bitcracker/bitlocker):
```
bitlocker$version$saltLen$saltHex$iterations$ivLen$ivHex$encryptedLen$encryptedHex
```

## Performance Notes
- This project implements cryptographic routines on-device and parallelizes candidate testing across GPU threads and blocks. Performance depends on GPU model, chosen thread/block configuration, and memory constraints. Use profiling and the `-t`/`-b` knobs to tune for your device.

## Roadmap & Limitations
- Single-GPU only (no multi-GPU orchestration yet).
- Full BitLocker recovery keyspace is extremely large; use range restrictions to make targeted recovery feasible.
- Contributions to add multi-GPU scheduling, CMake support, or improved host tooling are welcome.

## Contributing & License
- Follow `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` when contributing.
- This repository is distributed under GPL-3.0 (see `LICENSE`).

If anything in this README appears inconsistent with the code, the repository code and scripts are authoritative. If you want CMake support added, I can propose and add a `CMakeLists.txt` in a follow-up change.
