# ADR 0003: Produce real plans offline, with placeholder credentials and no network

- **Status:** Accepted

## Context

The end-to-end check needs real `terraform show -json` output, because that is what the rules
read in a user's repository. A real plan needs the real hashicorp/aws provider. The provider
normally validates credentials, looks up the account ID and may query instance metadata, all of
which need an AWS account; CI must not hold cloud credentials for this, and nothing in this
repository may ever deploy.

Options considered:

- **Mocked providers with `terraform test`** (used in multi-region-failover): no account needed,
  but the result is test state, not a plan file that conftest can read.
- **LocalStack:** a fake AWS API in Docker; heavier than needed, and the plan of new resources
  does not call the API at all.
- **A real sandbox account with read-only credentials:** realistic, but puts secrets in CI.
- **The real provider, configured not to call AWS:** `skip_credentials_validation`,
  `skip_requesting_account_id`, `skip_metadata_api_check` and `skip_region_validation`, with
  placeholder keys, and example configurations that use no data sources.

## Decision

Use the real provider offline. `scripts/tf.sh` is the only way Terraform runs here:

- It allows `init`, `validate`, `plan`, `show`, `fmt` and `version`, and refuses everything else
  (`apply`, `destroy`, `import`, state commands).
- It unsets every AWS credential source (profiles, session tokens, web identity, container
  credentials), points the shared config and credential files at paths that do not exist, turns
  off EC2 metadata, and sets placeholder keys that AWS would reject.
- After `init`, it sets `HTTPS_PROXY` and `HTTP_PROXY` to a closed local port, so any network
  call fails. The plans succeed, which shows the provider made no API call.
- It keeps the CLI config (`TF_CLI_CONFIG_FILE`), plugin cache (`TF_PLUGIN_CACHE_DIR`) and data
  directory (`TF_DATA_DIR`) under `.tmp/tf`, with `CHECKPOINT_DISABLE=1`.

## Consequences

- CI needs no secrets, and the plan JSON has exactly the shape a user's CI produces.
- Example configurations cannot use data sources (they would need the API); they use literal
  values instead. A user's own plan, produced with real credentials in their pipeline, is
  evaluated with the same `conftest test` command (`make check PLAN=...`).
- Terraform on Windows copies the 800 MB provider from the plugin cache into each data directory
  instead of linking it, so both examples share one data directory and the e2e script runs
  `init` before each example's plan; that `init` finds the provider already installed and does
  not download or copy it again.
