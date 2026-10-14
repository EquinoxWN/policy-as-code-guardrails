#!/bin/sh
# End-to-end check on real Terraform plans: plan both examples offline, export each plan with
# `terraform show -json`, and evaluate it with conftest. The compliant plan must pass every rule;
# the non-compliant plan must fail with exactly the messages in
# examples/noncompliant/expected-violations.txt, no more and no fewer.
set -eu

ext=
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) ext=.exe ;; esac
opa=.tmp/bin/opa$ext
conftest=.tmp/bin/conftest$ext
out=.tmp/plans
root=$(pwd -W 2>/dev/null || pwd)
mkdir -p "$out"

# fail MESSAGE: print it as a GitHub error annotation and stop.
fail() {
  echo "::error title=policy e2e::$1"
  exit 1
}

# query FILE EXPRESSION: evaluate a Rego expression over a JSON file and print the raw result.
query() {
  "$opa" eval --stdin-input --format raw "$2" <"$1"
}

rules=$(find policy/terraform -name '*.rego' ! -name '*_test.rego' | wc -l | tr -d ' ')

for example in compliant noncompliant; do
  plan="$root/$out/$example.tfplan"
  sh scripts/tf.sh "$example" init -input=false -no-color >"$out/$example.init.log"
  sh scripts/tf.sh "$example" plan -input=false -lock=false -no-color -out="$plan" >"$out/$example.plan.log"
  sh scripts/tf.sh "$example" show -json "$plan" >"$out/$example.json"
  echo "$example: $(grep -E '^Plan: ' "$out/$example.plan.log") (planned offline, exported with terraform show -json)"
done

for example in compliant noncompliant; do
  status=0
  "$conftest" test --no-color --all-namespaces --policy policy --output json "$out/$example.json" \
    >"$out/$example.conftest.json" || status=$?
  evaluated=$(query "$out/$example.conftest.json" \
    'count({r.namespace | some r in input; startswith(r.namespace, "terraform."); not endswith(r.namespace, "_test")})')
  [ "$evaluated" = "$rules" ] || fail "$example: conftest evaluated $evaluated rule packages, expected $rules"
  query "$out/$example.conftest.json" 'concat("\n", sort([f.msg | some r in input; some f in r.failures]))' \
    | sed '/^$/d' >"$out/$example.messages.txt"
  echo "$example: conftest exit $status, $(wc -l <"$out/$example.messages.txt" | tr -d ' ') violation(s), $rules rules evaluated"
  sed 's/^/  FAIL /' "$out/$example.messages.txt"
  case "$example" in compliant) compliant_status=$status ;; *) noncompliant_status=$status ;; esac
done

[ "$compliant_status" -eq 0 ] || fail "the compliant plan was rejected"
[ ! -s "$out/compliant.messages.txt" ] || fail "the compliant plan has violations"
[ "$noncompliant_status" -eq 1 ] || fail "conftest exited $noncompliant_status on the non-compliant plan, expected 1"
if ! diff -u --strip-trailing-cr examples/noncompliant/expected-violations.txt "$out/noncompliant.messages.txt"; then
  fail "the non-compliant plan's violations differ from examples/noncompliant/expected-violations.txt"
fi

expected=$(wc -l <examples/noncompliant/expected-violations.txt | tr -d ' ')
echo "::notice title=policy e2e::compliant plan passed all $rules rules; non-compliant plan blocked with exactly the $expected expected violations"
