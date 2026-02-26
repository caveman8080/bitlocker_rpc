# BitLocker RPC Copilot Instructions (maintainer-updated)

This document is intended for maintainers and automated assistants (Copilot-style agents) working on `bitlocker_rpc`. It documents the current architecture, recent changes, build/test workflows, and project-specific constraints. Treat this as the authoritative, living summary of the repository structure and traps-to-avoid.

## Important security & ethical notice
- This project is a security-sensitive tool. It is intended only for lawful, authorized recovery of BitLocker recovery passwords on drives you own or are explicitly authorized to recover. Do not assist in or automate any steps that facilitate unauthorized access. Always follow `SECURITY.md`, `CONTRIBUTING.md`, and `CODE_OF_CONDUCT.md` when contributing or responding to security reports.

## Project Overview (what the repo does)
- GPU-accelerated BitLocker recovery-password tester and candidate tester implemented in CUDA C++.
- Host responsibilities: parse hash, stage GPU work, monitor progress, write found password to `found.txt` or `-o` output.
- Device responsibilities: PBKDF2-HMAC-SHA256 (warp-optimized), AES block encrypt (AES-128/AES-256 device implementations), AES-CCM (generalized to accept key length and tag length), CTR decryption and CBC-MAC verification on-device.

## Architecture & Key Components (current)
- Main pipeline (host): `src/bitlocker_rpc.cu`
  - `parse_hash()` in `src/hash_parser.cpp` — parses `bitlocker$...` hashes (now accepts leading `$` variants).
  - Host memory allocation, kernel launches, profiling counters, and progress threads (`display_progress`, `display_gpu_utilization`).
- Password generation: `src/password_gen.cu` (maps index → recovery password format)
- GPU kernel: `src/kernel.cu` — `brute_force_kernel` launches device work, signals found password via `atomicCAS` into `d_found_flag` and writes `d_result_password`.
- Device crypto (src/crypto/):
  - `aes256.cu`, `aes128.cu` (AES-128 device encrypt added)
  - `aes_ccm.cu` generalized: accepts `key_len` (16/32) and `tag_len`, dispatches to AES-128 or AES-256 encryptors
  - `pbkdf2.cu`, `hmac_sha256.cu`, `sha256.cu` (warp-cooperative PBKDF2/HMAC)

## Recent notable changes
- Added AES-128 device implementation (`src/crypto/aes128.cu` / `aes128.h`) and dispatcher so `aes_ccm` supports both AES-128 and AES-256.
- Generalized `aes_ccm_decrypt` API to accept `key_len` and `tag_len` and handle S0 XOR per RFC-3610.
- Added RFC-3610 packet vector tests and a generator:
  - `scripts/generate_rfc_vectors.py` — fetches/parses RFC3610 and emits `src/tests/rfc_vectors.h` (used during test builds).
  - `src/tests/aes_ccm_rfc_test.cu`, `src/tests/aes_ccm_rfc_vectors.cu` — tests that validate AES-CCM against RFC vectors.
  - `src/tests/aes_ccm_test.cu`, `src/tests/aes_ccm_rand_test.cu` — roundtrip and randomized tests (existing, updated to new API).
- Updated `scripts/build_test.bat` and `scripts/build.bat` to include `aes128.cu` in test and main builds to avoid nvlink undefined symbol issues.
- Parser acceptance: `src/hash_parser.cpp` now accepts both `bitlocker$...` and `$bitlocker$...` variants (robust to leading `$` tokenization).

## Build & Run (maintainer notes)
- Primary build scripts:
  - Windows: `scripts/build.bat` — builds `build\bitlocker_rpc.exe` and test binaries.
  - Tests: `scripts/build_test.bat` — builds AES-CCM tests including RFC vectors generator output.
- NVCC flags used: `-rdc=true` is required for device-link across TUs; include `aes128.cu` explicitly in link objects when AES-128 symbols are referenced.

## Testing guidance
- Run unit tests locally before merging PRs:
  - `scripts\\build_test.bat` then run `build\\aes_ccm_test.exe`, `build\\aes_ccm_rand_test.exe`, `build\\aes_ccm_rfc_vectors.exe`.
- RFC vector generation:
  - `scripts/generate_rfc_vectors.py` downloads RFC3610 and writes `src/tests/rfc_vectors.h`. Keep network fetch optional in CI — check-in the generated `rfc_vectors.h` if you want fully offline tests.
- Keep randomized test counts reasonable for CI; heavy brute-force kernel runs should be gated and not run on shared CI.

## Debugging traps and gotchas
- Watch for nvlink undefined references when adding device symbols across TUs — include the TU explicitly in link or use `-rdc=true`.
- Do not assume fixed `TAG_LEN` in AES-CCM; use the generalized API's `tag_len` parameter.
- Avoid large shared-memory allocations per-thread; the AES warp-cooperative routines assume a maximum `threads_per_block` ≤ 256 to remain within shared buffer limits.

## Security & ethical reminders for automated agents
- Never attempt to brute-force real targets or automate actions that would access systems you do not own. For automated test runs, use synthetic or public test vectors under `src/tests/`.
- For any bug or vulnerability that could lead to unauthorized decryption or disclosure, create a private report following `SECURITY.md` and notify maintainers — do not open a public issue.

## Key files & quick references
- Host entry: `src/bitlocker_rpc.cu`
- Kernel: `src/kernel.cu`
- Hash parser: `src/hash_parser.cpp` and `src/include/hash_parser.h`
- Device crypto: `src/crypto/aes_ccm.cu`, `src/crypto/aes128.cu`, `src/crypto/aes256.cu`, `src/crypto/pbkdf2.cu`
- Tests: `src/tests/` (AES-CCM tests and RFC vector runner)
- Build scripts: `scripts/build.bat`, `scripts/build_test.bat`

---
**Feedback needed:** If any section is unclear, incomplete, or missing important project-specific knowledge, please specify which area and I will expand the instructions. If you want me to add exact example nvcc invocations for specific GPUs, say which GPU SM you target.
