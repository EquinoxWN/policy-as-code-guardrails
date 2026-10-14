# ADR 0002: Own rules in Rego, evaluated on plan JSON with conftest

- **Status:** Accepted

## Context

The guardrails must stop a pull request that would create a public bucket, an open
administrative port, a public or unencrypted database, or untagged resources. Three choices
shape everything else: what the rules read (HCL source or the plan), who writes the rules (us or
a scanner's vendor), and which engine runs them.

Ready-made scanners (Checkov, Trivy's misconfiguration checks, formerly tfsec) ship hundreds of
rules and need no code. Their rules, messages and exceptions are the vendor's, though, and
adding or adjusting one means learning the scanner's own rule format. HashiCorp Sentinel needs
HCP Terraform or Terraform Enterprise.

## Decision

- Write the rules ourselves in Rego (OPA 1.x syntax), one package per rule under
  `policy/terraform/<rule>/`, each exposing `deny contains msg` with a message that starts with
  the rule ID and the resource address.
- Evaluate the JSON of a real plan (`terraform show -json`), not the HCL: variables, module
  defaults, `default_tags`, `count` and `for_each` are already resolved there.
- Run the rules with conftest in CI (`--all-namespaces`) and test them with `opa test`, which
  share the same OPA engine version (1.21.2).
- Share plan handling in one library, `policy/lib/tfplan`, so every rule skips deletions and data
  sources the same way and resolves module references the same way.

## Consequences

- Every rule is readable and reviewable in the same pull request as its tests, and a message
  change is a test change. The cost is that coverage grows only as fast as we write rules: six
  in M1, against hundreds in a scanner. Running a scanner as well, as a non-blocking report, is
  compatible with this design.
- Plan JSON is only available after `terraform plan`, so the check needs a provider and runs at
  plan time, not on file save. In exchange it sees the values Terraform will actually send.
- Rego is also Gatekeeper's language, so the M2 Kubernetes rules reuse the same skills, test
  runner and CI pattern.
- Values only known at apply time are invisible to any plan-time check; each rule decides
  explicitly whether an unknown value counts as unsafe (see RFC 0001).
