# RFC 0001: policy-as-code-guardrails design

- **Status:** Accepted (M1 implemented)
- **Author:** EquinoxWN
- **Created:** 2026

## Problem

Many cloud breaches start with a configuration mistake rather than an exploit: a storage
bucket that anyone can read, SSH or a database port open to the whole internet, a database
with a public address, unencrypted disks. In a team that uses Terraform these mistakes are
written down in a pull request before they exist, so they can be caught there. Review by eye
does not do that reliably: a plan for a small change can list dozens of resources, the risky
value can come from a module default or a provider's `default_tags`, and reviewers check
different things on different days.

This project writes the checks as code (Rego), tests them like code, and runs them in CI on
the JSON that `terraform show -json` prints for a plan, so a pull request that would create one
of these mistakes fails before it merges.

## Users

- Platform and security engineers who maintain the rules and want them tested.
- Application teams who write Terraform and need a clear, early message telling them which
  resource breaks which rule and why.

## Goals

- **M1 (this RFC):**
  - Six rules in Rego, written against the plan JSON of the hashicorp/aws provider:
    PAC001 every S3 bucket has a full public access block (bucket- or account-level);
    PAC002 no S3 ACL or bucket policy grants access to everyone; PAC003 no administrative or
    database port is open to 0.0.0.0/0 or ::/0; PAC004 no publicly accessible RDS or Aurora
    instance; PAC005 RDS, Aurora and EBS storage explicitly encrypted; PAC006 required tags
    (`owner`, `environment`, `cost_center`) on every taggable resource, counting `default_tags`.
  - Every rule has unit tests with passing and failing fixtures, run by `opa test`, that check
    the exact message.
  - In CI, two example configurations are planned for real with Terraform, exported with
    `terraform show -json` and evaluated by conftest: the compliant plan must pass, the
    non-compliant plan must fail with exactly the expected messages. Any other outcome fails the
    pull request.
  - Nothing deploys anything: plans run without cloud credentials and with all network access
    blocked after `terraform init`.
- **M2:** Gatekeeper rules for Kubernetes (no privileged pods, resource limits required) and a
  policy coverage report.
- **M3:** audit mode for new rules, time-limited waivers, per-rule documentation of the risk, and
  a published example of a pull request blocked by a rule.

## Non-goals

- Scanning live cloud accounts (that is a CSPM product's job); this project checks changes
  before they apply.
- Covering every AWS service or other clouds in M1. The library and the rule layout make adding
  rules cheap, but M1 covers the six mistakes above.
- Replacing code review; the rules handle the checks that are mechanical.

## Critical-to-quality measures (Define)

| CTQ | Measure | Target for M1 |
|---|---|---|
| No false negative on the known mistakes | Every violation in the non-compliant example is reported, with the expected message | 11 of 11 expected messages, exact match |
| No false positive on a correct stack | Violations reported for the compliant example (modules, `for_each`, default tags, a Deny statement with `Principal: "*"`, HTTPS open to the internet) | 0 |
| Rules are tested on both sides | Rules with at least one passing and one failing unit fixture | 6 of 6; all tests pass |
| Tests catch rule bugs | Deliberate bugs (mutants) that make at least one unit test fail | 12 of 12 |
| Safe to run anywhere | AWS API calls during the end-to-end check; resources applied | 0 and 0 |
| Supply chain | Tool binaries verified against pinned and published SHA-256; known vulnerabilities in code they contain | 3 of 3 verified; none unaccepted |
| Fast feedback | Wall time of `opa test` and of the end-to-end check on the author's laptop | under 5 s and under 60 s |

## Proposed design

```
 terraform plan -out  ->  terraform show -json  ->  conftest test --all-namespaces --policy policy
   (scripts/tf.sh:          (plan JSON:                 (one Rego package per rule; deny contains msg)
    no credentials,          resource_changes,                     |
    offline after init)      configuration)          exit 0: merge allowed / exit 1: PR fails
```

- **Rules evaluate planned values.** Each rule reads `resource_changes[].change.after` through a
  small library (`policy/lib/tfplan`): only managed resources that will exist after apply are
  checked, so deletions and data sources never fail a plan.
- **Unknown values are handled per rule, explicitly.** Settings whose safe value must be set
  (public access block flags, encryption) count as unsafe when unknown at plan time, so a missing
  or computed value cannot slip through. Values that are often computed for harmless reasons
  (bucket policies built from bucket ARNs, security group rules filled in later) are skipped,
  and PAC001's `block_public_policy` makes AWS itself refuse a public policy at apply time.
- **Pairing resources across the plan.** A public access block covers a bucket when its planned
  `bucket` equals the bucket's name, or when the configuration section shows that its `bucket`
  argument refers to that bucket in the same module instance (and the same `count`/`for_each`
  key when both have one). This is what makes modules with `for_each` work without false alarms.
- **Messages are the interface.** Every message starts with the rule ID and the resource address
  and says what is wrong, for example
  `PAC003 aws_security_group.bastion: ingress from 0.0.0.0/0 to 22 (SSH)`.
- **Offline plans.** `scripts/tf.sh` refuses `apply`, `destroy`, `import` and state commands,
  clears every AWS credential source, gives the provider placeholder keys, keeps Terraform's CLI
  config, plugin cache and data directory inside `.tmp/`, and after `init` routes all HTTP(S)
  through a closed local port; a plan that succeeds therefore made no API call ([ADR 0003](../adr/0003-offline-plans-with-placeholder-credentials.md)).

## Alternatives considered

| Option | Why not (yet) |
|---|---|
| Checkov or tfsec/Trivy with built-in rules | Hundreds of ready rules, but the rules are not ours to read, test or change in the same review, and the goal here is a small, tested rule set whose every message we own. They remain a good complement ([ADR 0002](../adr/0002-rego-on-plan-json-with-conftest.md)). |
| HashiCorp Sentinel | Same idea, but it needs HCP Terraform or Terraform Enterprise; Rego runs anywhere and is reused by Gatekeeper in M2. |
| Checking the HCL source instead of the plan | Simpler input, but misses values from variables, module defaults, `default_tags`, `count` and `for_each`; the plan has them resolved. |
| Testing with mocked providers (`terraform test`) | Mocks produce state, not a plan JSON file for conftest; the real provider in an offline plan yields exactly the JSON that CI sees in a real repository. |
| LocalStack as a fake AWS | Needs Docker and a running service for something the plan alone answers. |

## Measurement plan (Measure, Control)

- `opa test policy -v`: test count, pass count, wall time.
- `scripts/mutate.sh`: mutants killed out of mutants made.
- `scripts/e2e.sh`: resources planned per example, conftest exit codes, violations reported against
  the expected list (exact diff), rule packages evaluated.
- `scripts/audit.sh`: govulncheck findings per binary against the accepted list.
- Results and the DMAIC analysis are in [docs/results/m1.md](../results/m1.md); every gate above
  runs in the `ci` workflow on each push and pull request.

## Milestones

- **M1 (done):** six rules, unit tests with passing and failing fixtures, mutation check, and the
  CI gate that plans the examples and fails on violations.
- **M2:** Gatekeeper constraints for Kubernetes; coverage report.
- **M3:** audit mode, time-limited waivers, per-rule risk documentation, a published blocked PR.

## Risks and open questions

- Plan-time checks see what Terraform knows before apply. A value computed only at apply time can
  hide a mistake; the rules either treat such values as unsafe or rely on a second control
  (PAC001's `block_public_policy`), and the README lists which.
- The pairing of buckets and access blocks reads the plan's `configuration` section; a reference
  through a local value or an output of another module is not followed, so such a bucket is
  reported unless its name is known at plan time (a false positive, never a false negative).
- The rules know the AWS provider's attribute names; a provider major version that renames them
  needs the fixtures and the examples updated, which the end-to-end check will show.
