# Security Policy

## Scope

This project downloads and installs agent instructions and may optionally execute a downloaded CLI smoke test. Treat every external repository as untrusted.

## Safe usage

- Review the repository and SKILL.md before installation.
- Prefer a commit SHA or immutable release tag.
- Use --dry-run first.
- Use --expected-sha256 when a trusted digest is available.
- Do not use --run-smoke-test unless the source is trusted and reviewed.
- Do not install into a directory that contains unrelated data.
- Keep --update-memory opt-in.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository when available. Do not open a public issue containing credentials, private paths, exploit details, or malicious payloads.

Include:

- affected version or commit
- operating system and shell
- minimal reproduction
- impact and suggested mitigation

## Supply-chain note

Installing a skill makes its instructions available to an agent. This installer cannot prove that a skill's prose is safe or appropriate; source review remains a required human step.

