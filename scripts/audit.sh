#!/bin/sh
# Known-vulnerability audit of every third-party binary this repository runs: OPA, conftest,
# Terraform and the AWS provider, scanned by govulncheck in binary mode with Go 1.26.8. A finding
# in code the binary contains fails the audit unless scripts/audit-accepted.txt lists it with a
# reason; an accepted ID that no binary reports any more is flagged so the list stays current.
set -eu
export GOTOOLCHAIN=go1.26.8

ext=
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) ext=.exe ;; esac
opa=.tmp/bin/opa$ext
provider=$(find .tmp/tf/plugin-cache -type f -name 'terraform-provider-aws_*' 2>/dev/null | head -n 1)
[ -n "$provider" ] || { echo "run make e2e first, so the AWS provider is in .tmp/tf/plugin-cache" >&2; exit 2; }

accepted=$(grep -Eo '^GO-[0-9]{4}-[0-9]+' scripts/audit-accepted.txt | sort -u)
mkdir -p .tmp/audit
seen=
failed=0

for binary in "$opa" ".tmp/bin/conftest$ext" ".tmp/bin/terraform$ext" "$provider"; do
  name=$(basename "$binary")
  sarif=.tmp/audit/$name.sarif
  go run golang.org/x/vuln/cmd/govulncheck@v1.8.0 -mode=binary -format sarif "$binary" >"$sarif"
  found=$("$opa" eval --stdin-input --format raw \
    'concat(" ", sort({r.ruleId | some run in input.runs; some r in run.results; r.level == "error"}))' <"$sarif")
  [ -n "$found" ] || echo "$name: no known vulnerability in the code it contains"
  for id in $found; do
    seen="$seen $id"
    if printf '%s\n' "$accepted" | grep -qx "$id"; then
      echo "$name: $id (accepted: see scripts/audit-accepted.txt)"
    else
      echo "::error title=audit::$name: $id is not accepted (https://pkg.go.dev/vuln/$id)"
      failed=1
    fi
  done
done

for id in $accepted; do
  case " $seen " in
    *" $id "*) ;;
    *) echo "::warning title=audit::$id is accepted but no longer reported; remove it from scripts/audit-accepted.txt" ;;
  esac
done

[ "$failed" -eq 0 ] || exit 1
echo "::notice title=audit::govulncheck found no unaccepted vulnerability in opa, conftest, terraform or the AWS provider"
