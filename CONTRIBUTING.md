# Contributing to bitlocker_rpc

Thank you for your interest in contributing to bitlocker_rpc. This document explains how to contribute code, tests, and documentation, and the project's expectations for quality, security, and legal/ethical compliance.

IMPORTANT: bitlocker_rpc is a security-sensitive tool intended only for lawful, authorized recovery of BitLocker recovery passwords on drives you own or are explicitly authorized to recover. Do not contribute code that makes it easier to misuse the project. All contributors must follow the Code of Conduct in `CODE_OF_CONDUCT.md` and the responsible disclosure guidance in `SECURITY.md`.

Table of contents
- Quick start
- Report issues and feature requests
- Development workflow and branching
- Build and test (developer guide)
- Code style and review checklist
- Tests and CI guidance
- Security and cryptography guidelines
- Licensing and contributor license

Quick start
1. Fork the repository and create a topic branch for your change: `git checkout -b feat/your-feature`.
2. Make focused commits with clear messages (one logical change per commit).
3. Run the project's build and tests locally (see Build and test section).
4. Open a pull request against `main` with a clear description and required test evidence.

Report issues and feature requests
- Use GitHub Issues for bug reports and feature requests. When filing a bug report include: reproduction steps, platform (Windows/Linux), CUDA toolkit and driver versions, `nvcc` output (if relevant), and any logs or test vectors.
- For potential security issues, follow `SECURITY.md` instead of opening a public issue.

Development workflow and branching
- Work on a branch named with a prefix (e.g., `fix/`, `feat/`, `chore/`, `doc/`).
- Keep branches small and focused. Rebase interactively to clean up WIP commits before PRs.
- Target branch: `main`. Long-lived feature branches should be coordinated with maintainers.

Build and test (developer guide)
These steps assume a development workstation with an NVIDIA GPU and CUDA Toolkit installed.

- Windows (PowerShell)
```powershell
cd <repo-root>
scripts\build.bat
# builds: build\bitlocker_rpc.exe and test binaries under build\
```
- Linux/macOS (example using nvcc directly)
```bash
cd <repo-root>
nvcc -gencode arch=compute_75,code=sm_75 -I src -I src/include -rdc=true -O3 \
  -o build/bitlocker_rpc \
  src/bitlocker_rpc.cu src/hash_parser.cpp src/kernel.cu src/password_gen.cu src/utils.cpp \
  src/crypto/aes_ccm.cu src/crypto/aes128.cu src/crypto/aes256.cu
```

Run tests
- Unit tests live under `src/tests/` and are built via `scripts/build_test.bat` on Windows. Example:
```powershell
scripts\build_test.bat
build\aes_ccm_test.exe
build\aes_ccm_rand_test.exe
build\aes_ccm_rfc_vectors.exe
```
- Run the RFC vectors and randomized tests locally before opening a PR.

Developer notes (common build issues)
- Ensure `aes128.cu` is linked into builds that reference AES-128 device symbols (some NVCC/NVML configurations require explicit TU inclusion).
- If you see nvlink undefined references, re-run builds with `-rdc=true` and include all crypto translation units.
- Suppress or address compiler warnings; do not introduce new ones without justification.

Code style and review checklist
- C++/CUDA style
  - Prefer clear, explicit names (no single-letter variable names for public interfaces).
  - Keep device-host code separation explicit; avoid host calls from device functions.
  - Follow existing project patterns (e.g., `CUDA_CHECK` macro usage, fixed buffer sizes in kernels).
- PR checklist (add to PR description)
  - Summary: one-paragraph description of the change.
  - Implementation notes: files changed and rationale.
  - Tests: description of new/updated tests and instructions to run them.
  - Security: analysis of any security implications (esp. crypto changes), and any mitigation.
  - Performance: if the change affects perf, include microbenchmark numbers and test harness used.

Tests and CI guidance
- Include unit tests for any crypto changes; verify against known-test vectors (RFC, randomized).
- Tests should be deterministic where possible; seed randomness explicitly in test harnesses.
- Keep test execution time reasonable for CI; long-running GPU brute-force tests should be optional or run on specialized CI runners.

Security and cryptography guidelines
- Changes to cryptographic code must be reviewed thoroughly: ensure constant-time where required, verify buffer sizes, and do not alter crypto primitives without explicit, documented justification.
- Avoid copying unvetted crypto implementations from the internet; prefer existing project device implementations and tests.
- Add RFC test vectors when implementing or changing authenticated encryption modes (AES-CCM); store vectors under `src/tests/` and ensure tests validate them.
- Do not include secret keys, private data, or private test vectors in commits. Use test vectors that are public or generated at test time.

Responsible disclosure
- If you find a vulnerability, DO NOT publicly disclose it. Follow `SECURITY.md` to report privately to maintainers.

Licensing and contributions
- This repository is licensed under GPL-3.0. By contributing, you agree that your contributions will be licensed under the project license.

Contact and governance
- For contribution questions, open an issue or contact the maintainers (see `CODE_OF_CONDUCT.md` for reporting contact).

Thank you for helping improve bitlocker_rpc.
