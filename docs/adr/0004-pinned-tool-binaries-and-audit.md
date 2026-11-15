# ADR 0004: Pinned tool binaries, a binary vulnerability audit, and no Regal in CI

- **Status:** Accepted

## Context

This repository has no package manifest: the third-party code it runs is the OPA, conftest and
Terraform release binaries and the hashicorp/aws provider. They need to be pinned, verified and
audited like any dependency. Regal, the Rego linter, was also considered as a fourth tool.

On 2026-10-08 `govulncheck -mode=binary` (v1.8.0, Go 1.26.8) reported:

| Binary | Findings in code the binary contains |
|---|---|
| OPA 1.21.2 | none |
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

## Update (2026-10-15)

The Go security release of 2026-10-08 left conftest, Terraform and the AWS provider without a fixed release. Accepting those IDs globally would also have hidden the same IDs in OPA, which does have a fixed release (1.21.2). `scripts/audit-accepted.txt` therefore names the binaries each ID is accepted for (a name with `.exe` means the Windows build only), and `scripts/audit.sh` flags an accepted pair that is no longer reported for a binary it scanned.

## Update (2026-10-30)

Terraform 1.17.1 (built with Go 1.26.10) and hashicorp/aws 6.71.0 (Go 1.27.3) no longer contain the IDs of the 2026-10-08 Go security release, so their entries were removed and both are accepted for GO-2026-5932 only. OPA 1.22.0 (Go 1.27.3) is clean. conftest 0.71.1 is still the latest release and is built with Go 1.27.1; besides the earlier IDs it now reports GO-2026-6809 (crypto/x509, fixed in Go 1.26.10 / 1.27.3) and GO-2026-6860 and GO-2026-6866 (`golang.org/x/net/html`, fixed in x/net 0.62.0). They are accepted for conftest only, because here it reads local Rego and plan JSON, verifies no TLS certificate and parses no HTML; any finding in the other three binaries still fails the build.

## Update (2026-11-15)

GO-2026-6859 (net/http HTTP/1 server crash, fixed in Go 1.26.11 / 1.27.4, published 2026-11-11) was reported in all four binaries. OPA 1.22.4 and hashicorp/aws 6.73.0 are built with Go 1.27.4, so OPA moved 1.22.0 -> 1.22.4 (also clean of GO-2026-6865) and the lock files moved 6.71.0 -> 6.73.0. Terraform moved 1.17.1 -> 1.17.2, which drops GO-2026-6865 (compress 1.20.2) but is still built with Go 1.26.10, so GO-2026-6859 is accepted for Terraform and conftest only: neither runs an HTTP server here. Any finding in OPA or the provider other than GO-2026-5932 still fails the build.
