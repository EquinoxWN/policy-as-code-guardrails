# Contributing

Thanks for helping. This is a Rego project with Terraform example configurations; issues and pull
requests are welcome.

## Set up and check your change

Needs `make`, a POSIX shell, `curl`, `unzip` and `tar` (Linux, or Git Bash on Windows), and Go 1.26
for the audit. `make setup` downloads the pinned OPA, conftest and Terraform into `.tmp/bin` and
verifies their SHA-256; every cache and plan stays in the git-ignored `.tmp/` folder. No cloud
account is needed.

```bash
make setup    # pinned, checksum-verified tools
make lint     # opa fmt --fail, opa check --strict, terraform fmt -check
make test     # opa test
make mutate   # the unit tests must catch every deliberate bug
make e2e      # real plans of the examples evaluated by conftest
make audit    # known-vulnerability check of the binaries (as in CI)
```

A pull request is ready when all of these pass and CI is green.

## Adding or changing a rule

- One package per rule in `policy/terraform/<rule>/<rule>.rego`, exposing `deny contains msg`,
  with a METADATA block (title, description, `custom.id`, `custom.severity`) and messages that
  start with the rule ID and the resource address.
- Read planned values through `data.lib.tfplan`, and decide explicitly whether a value unknown
  at plan time counts as unsafe; say which in the README's rule table.
- Add `<rule>_test.rego` beside it with at least one passing and one failing fixture, asserting
  the exact message; build fixtures with `data.lib.fixtures`.
- Add a mutation to `scripts/mutate.sh` for the rule's key condition.
- If the rule should fire on the non-compliant example, add the resource there and its message to
  `examples/noncompliant/expected-violations.txt`; the compliant example must stay clean.

## Guidelines

- Keep each change focused; explain the problem it solves in the pull request.
- Update `docs/results/` when numbers change.
- Significant design changes need an ADR in `docs/adr/` (copy `0001` for the format).
- Keep comments to one short phrase per rule or function; let names and tests explain the rest.
- Never add `apply` or credentials to the scripts: the examples are planned, never deployed.
- Report security problems privately, as described in [SECURITY.md](SECURITY.md).

By contributing you agree that your work is released under the [MIT License](LICENSE).
