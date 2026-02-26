# Security and Responsible Disclosure Policy

This project contains security-sensitive code (cryptographic routines, password-recovery tooling, and GPU-accelerated key-testing). If you discover a security vulnerability, please follow this responsible disclosure policy so we can address it promptly and safely.

Scope
- Any code paths that can lead to unauthorized access to data, bypass authentication, leak secrets, or allow remote/privileged code execution in the tool or its build/test infrastructure.
- Vulnerabilities in cryptographic implementations (wrong authentication handling, padding errors, side-channels, etc.).

What not to do
- Do not publish exploit code, private keys, or sensitive customer data publicly.
- Do not test vulnerabilities against systems you do not own or are not explicitly authorized to test.

How to report
1. Send an encrypted report to the maintainers at: security@example.com (PGP key preferred).
   - PGP key (fingerprint): 4A3B C1D2 E5F6 7890 DEADBEEFCAFEBABE0123456789ABCDEF
   - If you cannot use PGP, send a private email and request an encrypted channel.
2. In your report include:
   - A clear, concise description of the issue.
   - Steps to reproduce (minimal reproducer or test vectors). Do not include secrets or private data.
   - Impact assessment: what can be accessed or modified, and under what conditions.
   - Environment details: OS, CUDA driver, nvcc version, GPU model.
   - Suggested mitigation(s), if you have them.

Response timeline
- We will acknowledge receipt within 3 business days.
- We will provide a remediation plan or status update within 14 calendar days for most reports.
- For serious vulnerabilities requiring coordinated disclosure, we follow a 90-day disclosure timeline from the initial report; this may be extended by mutual agreement.

What we will (and will not) publish
- We will coordinate with the reporter on an appropriate disclosure plan. Public advisories will include affected versions, a description of the issue, and remediation steps.
- We will not include private keys, customer data, or proof-of-concept exploit code in public advisories.

Safe harbor
- If you act in good faith to report a potential security vulnerability following this policy, we will not pursue legal action against you. We expect researchers to follow the law and avoid privacy violations.

Acknowledgements
- We may offer public acknowledgement for reports that lead to a confirmed fix (unless you request anonymity).

Emergency contact
- If you believe the issue is being actively exploited and requires immediate attention, mark the email subject as **[SECURITY][URGENT]** and include all relevant indicators; also try to reach maintainers via any listed emergency contact channels.

Notes for researchers
- Avoid running large-scale brute-force attacks against production systems, or tests that could degrade service for legitimate users.
- Prefer small, self-contained reproducer test cases using the public test vectors in `src/tests/`.

Legal
- This policy does not grant you authorization to access any system you do not own. If you are unsure whether a test is authorized, do not perform the test and contact the maintainers first.

Contact placeholder
- Replace `security@example.com` and the PGP fingerprint above with the project's monitored security contact and key.
