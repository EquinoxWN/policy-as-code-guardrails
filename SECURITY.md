# Security policy

## Reporting a vulnerability

Please report security problems privately through GitHub:
**Security > Report a vulnerability** on this repository
(`https://github.com/EquinoxWN/policy-as-code-guardrails/security/advisories/new`). Do not open a public issue.

Include what you found, how to reproduce it, and the impact you expect. You will get an answer
within 7 days. Fixes are released as soon as they are ready, and you are credited unless you ask
not to be.

## Supported versions

This project is pre-1.0. Only the latest commit on `main` receives fixes.

## Scope

- **In scope:** A Terraform plan with a public bucket, an open administrative or database port,
  a public or unencrypted database, or missing tags that the rules let through (a false
  negative); a way to make `scripts/tf.sh` apply changes, use real cloud credentials or reach the
  network after `init`; a way to run an unverified tool binary.
- **Out of scope:** Mistakes in resource types or AWS services the rules do not cover yet (see
  the rule table in the README), and values that are only known after apply, which no plan-time
  check can see.

## How this repository protects itself

- Every GitHub Action is pinned to a full commit SHA, and workflows run with read-only
  permissions and without persisted credentials.
- OPA, conftest and Terraform are pinned by version and SHA-256, and checked against the
  checksums each project publishes; the AWS provider is pinned by the committed lock files.
- Dependabot update pull requests are paused (`open-pull-requests-limit: 0`) so the repository keeps a single `main` branch; dependencies are updated by hand and checked by the CI audit.
- CI runs lint, unit tests, a mutation check, the end-to-end plan check and a known-vulnerability
  audit (govulncheck on every tool and provider binary) on every push and pull request.
