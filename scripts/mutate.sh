#!/bin/sh
# Mutation check for the unit tests: copy the policies, break one rule in a realistic way, and
# require `opa test` to report failing tests. A mutant that still passes means a gap in the tests.
set -eu

ext=
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) ext=.exe ;; esac
opa=.tmp/bin/opa$ext
work=.tmp/mutants
total=0
killed=0

# mutate FILE OLD NEW DESCRIPTION: replace the first literal OLD in a copy of FILE and run the tests.
mutate() {
  total=$((total + 1))
  rm -rf "$work"
  mkdir -p "$work"
  cp -R policy "$work/policy"
  if ! old="$2" new="$3" awk '
    !done && (i = index($0, ENVIRON["old"])) {
      $0 = substr($0, 1, i - 1) ENVIRON["new"] substr($0, i + length(ENVIRON["old"]))
      done = 1
    }
    { print }
    END { exit !done }
  ' "policy/$1" >"$work/policy/$1"; then
    echo "mutation $total ($4): text not found in policy/$1" >&2
    exit 1
  fi
  status=0
  "$opa" test "$work/policy" >"$work/result.txt" 2>&1 || status=$?
  if grep -q '^FAIL: ' "$work/result.txt"; then
    killed=$((killed + 1))
    caught=$(sed -n 's|^FAIL: \([0-9]*\)/\([0-9]*\)$|\1 of \2|p' "$work/result.txt")
    printf 'killed   %2d: %s (caught by %s tests)\n' "$total" "$4" "$caught"
  elif [ "$status" -eq 0 ]; then
    printf 'SURVIVED %2d: %s\n' "$total" "$4"
  else
    cat "$work/result.txt" >&2
    echo "mutation $total ($4) does not compile; fix the mutation" >&2
    exit 1
  fi
}

mutate lib/tfplan/tfplan.rego 'rc.change.after != null' 'true' \
  'resources planned for deletion are checked too'
mutate lib/tfplan/tfplan.rego 'regex.replace(module_address(rc),' 'regex.replace("",' \
  'module paths are ignored when resolving references'
mutate terraform/s3_public_access_block/s3_public_access_block.rego 'tfplan.after(block, setting, false)' \
  'tfplan.after(block, setting, true)' 'a public access block setting unknown at plan time counts as on'
mutate terraform/s3_public_access_block/s3_public_access_block.rego '	same_instance(block, bucket)' '	true' \
  'a block in one count or for_each instance covers every instance'
mutate terraform/s3_public_grants/s3_public_grants.rego '"authenticated-read"}' '}' \
  'the authenticated-read canned ACL is allowed'
mutate terraform/s3_public_grants/s3_public_grants.rego 'lower(key) in narrowing_keys' 'is_string(key)' \
  'any condition makes a wildcard principal acceptable'
mutate terraform/sg_open_ingress/sg_open_ingress.rego 'endswith(source, "/0")' 'source == "0.0.0.0/0"' \
  'IPv6 ::/0 is not treated as the internet'
mutate terraform/sg_open_ingress/sg_open_ingress.rego 'port <= rule.to' 'port < rule.to' \
  'the last port of a range is not checked'
mutate terraform/sg_open_ingress/sg_open_ingress.rego '{"-1", "all"}' '{"all"}' \
  'protocol -1 (every protocol) is not treated as every port'
mutate terraform/db_public_access/db_public_access.rego ', "aws_rds_cluster_instance"}' '}' \
  'public Aurora instances are not checked'
mutate terraform/encryption_at_rest/encryption_at_rest.rego 'tfplan.after(rc, attribute, false)' \
  'tfplan.after(rc, attribute, true)' 'encryption left unset is trusted to an account default'
mutate terraform/required_tags/required_tags.rego 'trim_space(value) != ""' 'value != ""' \
  'a blank tag value counts as set'

rm -rf "$work"
echo "$killed of $total mutants killed"
if [ "$killed" -ne "$total" ]; then
  echo "::error title=mutation check::$((total - killed)) of $total mutants survived the unit tests"
  exit 1
fi
echo "::notice title=mutation check::all $total mutants killed by the unit tests"
