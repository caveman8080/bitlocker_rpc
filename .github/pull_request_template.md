## Summary
Short description of the change and the problem it addresses.

## Checklist
- [ ] I have read the CONTRIBUTING guidelines.
- [ ] Code builds and runs locally.
- [ ] Relevant tests added/updated.
- [ ] Documentation updated if required.

## How to test
Steps to reproduce or test the change locally, including any build commands.

## Notes
Anything the reviewer should specifically look at (performance, thread-safety, API changes).

## Crypto / Security Checklist
- **Crypto changes:** Describe which cryptographic primitives were modified and why.
- **RFC vectors/tests:** Include RFC or public test vectors under `src/tests/` and reference them here.
- **Constant-time:** State whether constant-time requirements apply and how they were validated.
- **Secrets:** Confirm no private keys, credentials, or secret test vectors are committed.
- **Manual security review:** Add the `security` label and request a maintainer security review for crypto-sensitive changes.
- **Disclosure plan:** If the change alters the vulnerability surface, include a coordinated disclosure plan and reference `SECURITY.md`.
<!-- Please describe the change in a single concise paragraph. -->
