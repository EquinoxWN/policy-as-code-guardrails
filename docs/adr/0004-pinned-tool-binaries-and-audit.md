# ADR 0004: Pinned tool binaries, a binary vulnerability audit, and no Regal in CI

- **Status:** Accepted

## Context

This repository has no package manifest: the third-party code it runs is the OPA, conftest and
Terraform release binaries and the hashicorp/aws provider. They need to be pinned, verified and
audited like any dependency. Regal, the Rego linter, was also considered as a fourth tool.

On 2026-10-08 `govulncheck -mode=binary` (v1.8.0, Go 1.26.8) reported:

| Binary | Findings in code the binary contains |
|---|---|
| OPA 1.21.1 | none |
| conftest 0.71.1 | GO-2026-5932 (`golang.org/x/crypto/openpgp` unmaintained, no fixed version) |
| Terraform 1.16.5 | GO-2026-5932 |
| hashicorp/aws 6.67.0 | GO-2026-5932 |
| Regal 0.43.0 | 35, from its Go 1.26.0 standard library and `golang.org/x/crypto` 0.55.0, all fixed upstream but not in a Regal release yet |

## Decision

- `scripts/tools.sh` pins each tool's version and SHA-256 for Linux and Windows on amd64, and
  checks each download against both the pinned hash and the checksum file that the project
  publishes for that release. A changed version string forces a fresh, verified download.
- `scripts/audit.sh` scans all four binaries in CI. A finding fails the build unless
  `scripts/audit-accepted.txt` lists its ID with a reason; an accepted ID that is no longer
  reported raises a warning so the list cannot go stale. GO-2026-5932 is accepted, because no
  fixed version exists and it ships in the latest release of every affected tool.
- Regal is not part of the toolchain. The policies were linted with Regal 0.43.0 once during M1
  and all 37 findings were fixed (string interpolation, line length, function style, entrypoint
  annotations); CI keeps `opa fmt --fail` and `opa check --strict` as the lint gate.

## Consequences

- No unverified binary runs, locally or in CI, and the audit is part of every build.
- The accepted list is an explicit, reviewable exception rather than a silenced scanner.
- Without Regal in CI, Rego style can drift. Re-adding it is one line in `tools.sh` and one in
  the Makefile once a Regal release no longer carries known vulnerabilities.
- Dependabot cannot bump versions pinned in a shell script; it covers the GitHub Actions and the
  AWS provider in the lock files, and the tool versions are reviewed by hand.
