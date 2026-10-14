.PHONY: setup lint test mutate e2e check audit ci

# OPA, conftest and Terraform are downloaded into .tmp/bin by scripts/tools.sh (pinned versions,
# SHA-256 checked); Terraform only ever runs through scripts/tf.sh (offline, no cloud credentials).
EXE := $(if $(filter Windows_NT,$(OS)),.exe,)
OPA := .tmp/bin/opa$(EXE)
CONFTEST := .tmp/bin/conftest$(EXE)
export CHECKPOINT_DISABLE := 1

setup:
	sh scripts/tools.sh

# Rego formatting and strict compilation; Terraform formatting of the example configurations.
lint:
	$(OPA) fmt --list --fail policy
	$(OPA) check --strict policy
	sh scripts/tf.sh compliant fmt -check -recursive ..

# Unit tests: a passing and a failing fixture for every rule, with exact messages.
test:
	$(OPA) test policy -v

# Twelve deliberate bugs in copies of the policies; the unit tests must catch every one.
mutate:
	sh scripts/mutate.sh

# Real plans: terraform plan + show -json on both examples, then conftest; see scripts/e2e.sh.
e2e:
	sh scripts/e2e.sh

# Evaluate your own plan: terraform show -json plan.tfplan > plan.json && make check PLAN=plan.json
check:
	@test -n "$(PLAN)" || { echo "usage: make check PLAN=path/to/plan.json"; exit 2; }
	$(CONFTEST) test --all-namespaces --policy policy "$(PLAN)"

# govulncheck (binary mode) on opa, conftest, terraform and the AWS provider; needs Go and make e2e.
audit:
	sh scripts/audit.sh

ci: setup lint test mutate e2e
