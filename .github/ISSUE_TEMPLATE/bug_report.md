---
name: Bug report
about: Create a report to help us improve the project and reproduce failures
title: "[BUG] "
labels: bug
assignees: ''
---

**Important — security issues:** Do NOT include sensitive data, private keys, or exploit details in a public issue. If your report describes a security vulnerability, follow `SECURITY.md` and report privately to the maintainers.

Describe the bug
----------------
- A clear and concise description of what the bug is.

Steps to reproduce
------------------
Provide a minimal set of steps to reproduce the behavior:

1. Build command used (example): `scripts\build.bat` or `nvcc ...`
2. Exact command-line invocation used (example): `build\bitlocker_rpc.exe -f hash.txt -t 128 -b 128`
3. Any input files or minimal reproducer (attach small sample if possible)

Expected behavior
-----------------
- A clear description of what you expected to happen.

Actual behavior
---------------
- What actually happened instead. Include console output or error messages.

Environment
-----------
- OS (Windows/Linux/macOS) and version
- GPU model and driver version
- CUDA toolkit / `nvcc` version
- Commit SHA or tag of the repository

Logs & artifacts
----------------
- Attach console logs, build output, or test output. Redact any secrets.

Optional: additional context
----------------------------
- Anything else that might help (screenshots, notes, test vectors).
