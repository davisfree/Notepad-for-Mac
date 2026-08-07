# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| latest release | ✅ |
| previous release | ✅ (until the next release ships) |

## Reporting a Vulnerability

Please **do not open a public issue** for security vulnerabilities.

To report a vulnerability privately:

1. Use GitHub's **Private vulnerability reporting**: repo → *Settings* → *Security* → *Private vulnerability reporting* → *New draft security advisory* (must be enabled in the repo settings).
2. Or email the maintainers at `security@notepadmac.example` (placeholder — replace with a real address before publicizing the project).

You can expect a response within **7 days**. If the issue is confirmed, a fix will be shipped as a patch release as soon as possible, and the advisory will be published after the fix lands.

## Scope

- Remote code execution, file-system access beyond the user-selected files, crash-inducing inputs, and privacy leaks (session backups, crash reports) are all in scope.
- Crash reports are **anonymized** by design: file paths and content fragments are redacted before upload (see `01_TECH_SPEC.md` §5).
