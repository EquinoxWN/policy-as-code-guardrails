#!/bin/sh
# Run the pinned Terraform on one example configuration, offline and without cloud credentials.
# usage: sh scripts/tf.sh <example> <init|validate|plan|show|fmt|version> [args...]
set -eu

if [ $# -lt 2 ]; then
  echo "usage: sh scripts/tf.sh <example> <init|validate|plan|show|fmt|version> [args...]" >&2
  exit 2
fi
example=$1
command=$2
shift 2

# Only examples that exist in this repository, so a typo cannot point Terraform elsewhere.
case "$example" in
  */* | *..* | "") echo "example must be a folder name under examples/" >&2; exit 2 ;;
esac
[ -f "examples/$example/main.tf" ] || { echo "no examples/$example/main.tf" >&2; exit 2; }

# Nothing here may change real infrastructure: apply, destroy, import and state edits are refused.
case "$command" in
  init | validate | plan | show | fmt | version) ;;
  *) echo "refused: terraform $command (only init, validate, plan, show, fmt and version are allowed)" >&2; exit 2 ;;
esac

root=$(pwd -W 2>/dev/null || pwd)
ext=
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) ext=.exe ;; esac
terraform="$root/.tmp/bin/terraform$ext"
[ -x "$terraform" ] || { echo "run sh scripts/tools.sh first" >&2; exit 2; }

# Every Terraform file stays inside .tmp: CLI config, plugin cache and data dir. The data dir is
# shared by the examples because Terraform on Windows copies the 800 MB provider into each one;
# run init before validate or plan whenever you switch examples (scripts/e2e.sh does).
tf=$root/.tmp/tf
mkdir -p "$tf/plugin-cache" "$tf/data"
: >"$tf/terraformrc"
export TF_CLI_CONFIG_FILE="$tf/terraformrc"
export TF_PLUGIN_CACHE_DIR="$tf/plugin-cache"
export TF_DATA_DIR="$tf/data"
export TF_IN_AUTOMATION=1 TF_INPUT=0 CHECKPOINT_DISABLE=1

# No real AWS identity can be picked up: profiles, tokens, roles and instance metadata are cleared,
# and the provider gets placeholder keys that AWS would reject if any API call were made.
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_ROLE_ARN \
  AWS_WEB_IDENTITY_TOKEN_FILE AWS_CONTAINER_CREDENTIALS_FULL_URI \
  AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_CONTAINER_AUTHORIZATION_TOKEN
export AWS_ACCESS_KEY_ID=offline-plan-placeholder AWS_SECRET_ACCESS_KEY=offline-plan-placeholder
export AWS_SHARED_CREDENTIALS_FILE="$tf/no-aws-credentials" AWS_CONFIG_FILE="$tf/no-aws-config"
export AWS_EC2_METADATA_DISABLED=true

# Only init needs the network (the provider download); everything after it is forced offline by
# sending all HTTP(S) through a closed local port, so a plan that succeeds made no API call.
if [ "$command" != init ]; then
  export HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 NO_PROXY=
fi

exec "$terraform" -chdir="examples/$example" "$command" "$@"
