<!-- Maintainer-updated Copilot instructions for automated assistants -->

# BitLocker RPC Copilot Instructions (maintainer-updated)

This file documents project context and safe assistant behavior for maintainers and automated Copilot-style agents working on `bitlocker_rpc`.

Purpose
- Provide a short, actionable summary of the repository, build/test commands, recent risky areas, and explicit safety rules for automated agents.

High-level rules for automated agents
- This is a security-sensitive project. Do not assist in unauthorized access, exploitation, or data exfiltration.
- If a user requests actions that facilitate unauthorized access (brute-forcing a third-party target, automating exploits, etc.), respond only with: "Sorry, I can't assist with that." and provide responsible-disclosure guidance if appropriate.
- When drafting or editing code that handles cryptographic primitives, add tests using public RFC vectors and flag the change for manual security review in the PR description.

Project summary
- Purpose: GPU-accelerated BitLocker recovery-password candidate tester implemented in CUDA C++.
- Host responsibilities: hash parsing, staging GPU work, progress reporting, writing results to disk.
- Device responsibilities: PBKDF2-HMAC-SHA256, AES block encrypt (AES-128/256), AES-CCM, CTR decrypt/CBC-MAC verify, and candidate generation kernels.

Key files and quick pointers
- `src/bitlocker_rpc.cu`: main host flow, CLI, device launches, and multi-GPU coordination.
- `src/password_gen.cu`: maps numeric index → recovery-password string and supports mask mode.
- `src/kernel.cu`: brute-force kernel; look for `brute_force_kernel` and device-found signaling (`d_found_flag`).
- `src/crypto/`: AES/PBKDF2/HMAC/sha256 device implementations and AES-CCM glue.
- `scripts/build.bat`, `scripts/build_test.bat`: Windows build/test entrypoints maintained for CI compatibility.

Recent risky/interesting areas
- AES-CCM generalization: `aes_ccm.cu` accepts variable key and tag lengths; keep tag handling correct.
- Multi-GPU orchestration and keyspace splitting: review off-by-one keyspace boundaries and per-device start/end indices.
- Device symbol uploads (mask arrays, found flags): ensure `cudaMemcpyToSymbol` and synchronization are correct.

Build & test (quick commands)
- Windows (PowerShell):
```powershell
cd <repo-root>
scripts\build.bat
scripts\build_test.bat
```
- Linux/macOS example (nvcc):
```bash
nvcc -gencode arch=compute_75,code=sm_75 -I src -I src/include -rdc=true -O3 \
  -o build/bitlocker_rpc \
  src/bitlocker_rpc.cu src/hash_parser.cpp src/kernel.cu src/password_gen.cu src/utils.cpp \
  src/crypto/aes_ccm.cu src/crypto/aes128.cu src/crypto/aes256.cu
```

Testing guidance for crypto changes
- Add RFC vectors under `src/tests/` and make test harnesses run quickly by default.
- Keep heavy brute-force tests gated behind `--slow` or CI labels and do not run on shared CI.

How to handle security reports
- Do not post exploit details publicly. Follow `SECURITY.md` for contact and encrypted reporting.
- If an automated scan or static analysis reveals a potential vulnerability, create a private issue and add the `security` label for maintainers to triage.

Examples of assistant-safe responses
- If asked to help run a brute-force attack on a target you don't own: "Sorry, I can't assist with that. If you believe you've found a vulnerability, please report it via SECURITY.md."
- If asked to add PGP keys or responsible-disclosure contact to `SECURITY.md`: proceed after confirming the user is an authorized maintainer.

When to escalate to a human maintainer
- Any code change that weakens cryptographic checks, exposes secret material, automates credential collection, or changes the attack surface.

Feedback and maintenance
- Keep this file short and up-to-date when adding new risky features (multi-GPU, mask-mode, benchmark-only paths). Notify maintainers via PR.

---

If you'd like, I can now:
- Add maintainer contact details into `SECURITY.md` (PGP key already present).
- Create a short checklist to include in PR templates for crypto/security review.
