# Contributing to bitlocker_rpc

Thank you for helping improve `bitlocker_rpc`. This guide explains how to build, test, and contribute code, documentation, and benchmarks while keeping security and quality high.

IMPORTANT: `bitlocker_rpc` is a security-sensitive tool. Only work on targets you own or are explicitly authorized to test. Follow `CODE_OF_CONDUCT.md` and `SECURITY.md` for disclosure guidance.

Table of contents
- Quick start
- Build & test
- Benchmarking and performance runs
- Development workflow
- Coding guidelines & PR checklist
- Tests and CI
- Security & crypto guidance
- License and contribution terms

Quick start
1. Fork the repository and create a branch: `git checkout -b feat/your-feature`.
2. Make focused commits with clear messages (one logical change per commit).
3. Run the build and tests locally. Run benchmarks if your change impacts performance.
4. Open a pull request targeting `main` with a description, test results, and any performance numbers.

Build & test
Prerequisites: NVIDIA GPU, CUDA Toolkit (matching driver), a C++ toolchain (MSVC/clang/gcc), and `nvcc` on PATH for non-Windows builds.

Windows (PowerShell):
```powershell
cd <repo-root>
scripts\build.bat
# produces: build\bitlocker_rpc.exe and test binaries in build\
```

Build tests (Windows):
```powershell
scripts\build_test.bat
# run test exes under build\
```

Linux/macOS (example):
```bash
cd <repo-root>
nvcc -gencode arch=compute_75,code=sm_75 -I src -I src/include -rdc=true -O3 \
  -o build/bitlocker_rpc \
  src/bitlocker_rpc.cu src/hash_parser.cpp src/kernel.cu src/password_gen.cu src/utils.cpp \
  src/crypto/aes_ccm.cu src/crypto/aes128.cu src/crypto/aes256.cu
```

Benchmarking and performance runs
- Use the program's benchmark mode to measure throughput without full crypto verification: `build\\bitlocker_rpc.exe -B -t <threads> -b <blocks>`.
- For device-level throughput testing, run one device at a time and report GPU model and CUDA driver/toolkit versions with results.
- For multi-GPU tests, ensure each GPU is pinned and runs a distinct keyspace slice; document how you split the keyspace in your PR.

Development workflow
- Branch naming: `fix/`, `feat/`, `chore/`, `doc/`.
- Keep PRs small and focused; prefer multiple small PRs over large monoliths.
- Rebase/squash WIP commits before merging to keep history clean.

Coding guidelines & PR checklist
- Language: C++17/CUDA where applicable. Follow the existing project style.
- Avoid single-letter names in public APIs; prefer explicit, self-documenting names.
- Device vs host: keep separation clear; avoid host-only APIs on device code.

PR description checklist (include in PR body):
- **Summary:** one-paragraph description.
- **Files changed & rationale.**
- **Testing:** how to run tests and sample outputs.
- **Security:** note any crypto/security impact and mitigations.
- **Performance:** microbenchmark numbers and test harness used (if applicable).

Pre-commit / hooks (recommended)
- Use `clang-format` if available for C++ formatting; keep diffs minimal.
- Optionally add a git hook to run unit tests or linters before pushing.

Tests and CI
- Unit tests live in `src/tests/`. Add deterministic tests for crypto primitives and RFC vectors when relevant.
- Keep CI-friendly tests fast. Long GPU brute-force runs should be optional and gated behind explicit flags or special runners.

Security & cryptography guidance
- Crypto changes require careful review. Preserve constant-time properties where required and validate against RFC test vectors.
- Do not commit secret keys, private test vectors, or production private data. Use public test vectors or generate at test time.
- Report vulnerabilities privately following `SECURITY.md`.

License and contribution terms
- The project is licensed under GPL-3.0. By contributing you agree to license your contributions under the same terms.

Contact and governance
- For questions, open an issue. For potential security issues, follow `SECURITY.md` and include encrypted details if needed.

Thank you for contributing to `bitlocker_rpc`.
