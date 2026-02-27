---
![GPU:Cuda](https://img.shields.io/badge/GPU-CUDA-orange) ![Language:C%2B%2B](https://img.shields.io/badge/Language-C%2B%2B-blue) ![License:GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-green)

# bitlocker_rpc — GPU-accelerated BitLocker Recovery Password Tester

One-line: High-throughput CUDA C++ implementation to test BitLocker recovery-password candidates for lawful, authorized recovery of your own drives.

Contents
- [Features](#features)
- [Legal & Ethical Disclaimer](#legal--ethical-disclaimer)
- [How BitLocker Recovery Passwords Work](#how-bitlocker-recovery-passwords-work)
- [Hardware & Software Requirements](#hardware--software-requirements)
- [Build Instructions](#build-instructions)
- [Usage](#usage)
- [Benchmark (measured)](#benchmark-measured)
- [Performance Notes](#performance-notes)
- [Roadmap & Limitations](#roadmap--limitations)
- [Contributing & License](#contributing--license)

## Features
- CUDA-accelerated candidate generation and testing for the 48-digit BitLocker recovery password format (8 groups of 6 digits).
- Device-side implementations of cryptographic primitives used by BitLocker (PBKDF2-HMAC-SHA256, AES-CCM, AES-128/256) for maximum throughput.
- Command-line tuning: configurable `-t` (threads per block) and `-b` (blocks) for GPU tuning.
- Optional `--benchmark` mode to exercise password-generation throughput without performing the full crypto verification.
- Unit tests for AES-CCM (RFC vectors and randomized tests) included under `src/tests/`.

## Legal & Ethical Disclaimer
THIS PROJECT IS A SECURITY-SENSITIVE TOOL. Use of this software to access or attempt to access data without explicit authorization is illegal and unethical. By using this software you confirm that you are the owner of the target device or otherwise have explicit written authorization to perform recovery operations on it.

- Do not use this software for unauthorized access, penetration testing without permission, or any activity that violates local laws or terms of service.
- The authors and maintainers accept no liability for misuse. Use at your own risk.
- For responsible disclosure of vulnerabilities related to this project, see `SECURITY.md`.

If you are not sure whether you are authorized to recover a disk or system, stop and obtain written permission before proceeding.

## How BitLocker Recovery Passwords Work
BitLocker recovery passwords are typically 48-digit numeric values displayed as 8 groups of 6 decimal digits (e.g. `111111-222222-...`). Each 6-digit block often encodes a checksum; common recovery-password generation schemes require the 6-digit group to be divisible by 11. This tool generates candidate passwords in the canonical 8x6 format, derives the keys used by BitLocker, and tests candidates on the GPU.

## Hardware & Software Requirements
- NVIDIA GPU with CUDA support and an installed CUDA Toolkit (nvcc). Tested with CUDA Toolkit compatible with your GPU driver.
- Windows (MSVC toolchain) or Linux (gcc) supported via `nvcc`.
- Sufficient GPU memory for your workload and CUDA-capable drivers.
- Build tools: Visual Studio Build Tools (Windows) or standard build essentials (Linux) for host compilation.

The repository includes platform-specific scripts in `scripts/` to assist building on Windows and Unix-like systems.

## Build Instructions
This project includes convenience build scripts. Two primary approaches are shown below: using the included scripts, or a manual `nvcc` invocation.

1) Recommended: Use the platform script

Windows (PowerShell):
```powershell
cd <repo-root>
scripts\build.bat
```

Linux / macOS (bash):
```bash
cd <repo-root>
scripts/build.sh
```

2) Manual `nvcc` (example)

Adjust `-gencode` / SM flags as appropriate for your GPU (see `nvidia-smi` for compute capability). Example:
```bash
nvcc -gencode arch=compute_75,code=sm_75 -I src -I src/include -rdc=true -O3 \
  -o build/bitlocker_rpc \
  src/bitlocker_rpc.cu src/hash_parser.cpp src/kernel.cu src/password_gen.cu src/utils.cpp \
  src/crypto/aes_ccm.cu src/crypto/aes128.cu src/crypto/aes256.cu
```

3) Optional: CMake

This repository does not include an official `CMakeLists.txt` by default. You may create a simple `CMakeLists.txt` to wrap `nvcc` or invoke `nvcc` via a custom target. If you want, open an issue and I can propose a canonical `CMakeLists.txt` that matches the source layout.

## Usage
Show help:
```powershell
build\bitlocker_rpc.exe -h
```

Run with a BitLocker-style hash file or inline hash (see `README` hash format below). Example (benchmark-only):
```powershell
build\bitlocker_rpc.exe -B -t 128 -b 128
```

### Hash format accepted
The program accepts the Bitcracker/bitlocker format:
```
bitlocker$version$saltLen$saltHex$iterations$ivLen$ivHex$encryptedLen$encryptedHex
```
The easiest way to obtain such a hash is to use an extraction utility such as Bitcracker's HashExtractor; follow their instructions and ensure you have authorization to extract the hash.

## Benchmark (measured)
The table below records an on-host measured throughput using the repository's `--benchmark` mode with `-b 128` (blocks) and `-t 128` (threads per block) on the default GPU device present during this run.

| Device | Blocks | Threads | Duration cap | Throughput (M keys/sec) |
|--------|--------:|--------:|:------------:|------------------------:|
| Default GPU (detected at runtime) | 128 | 128 | 10s cap | 529.66 |

Notes: The above value was measured on the current machine when `scripts/build.bat` produced `build\\bitlocker_rpc.exe` and `--benchmark` was executed as shown in the Usage section.

## Performance Notes
- Throughput depends strongly on GPU architecture, SM count, clock, memory bandwidth, and host-to-device latency.
- Use the `-t` and `-b` knobs to tune occupancy. Larger blocks/threads increase parallelism but may hit shared-memory or register limitations.
- `--benchmark` mode exercises password generation only (skips full crypto verify) and is useful for microbenchmarking generator throughput.

## Roadmap & Limitations
- Multi-GPU orchestration: planned to split ranges across multiple CUDA devices efficiently.
- CMake integration: optional contribution to provide a canonical cross-platform `CMakeLists.txt`.
- This tool does not perform any automated extraction of protected volumes — use appropriate extraction tools and legal permission.

## Contributing & License
Contributions are welcome under the following rules:
- Follow `CONTRIBUTING.md` and the `CODE_OF_CONDUCT.md` included in this repository.
- For security-related issues, follow `SECURITY.md` and provide responsible disclosure.

License: This repository is distributed under GPL-3.0. See `LICENSE` for full terms.

---
