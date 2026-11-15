#!/bin/sh
# Download the pinned OPA, conftest and Terraform releases into .tmp/bin. Each download must
# match the SHA-256 pinned below and the checksum file the project publishes for that release.
set -eu

OPA_VERSION=1.22.4
CONFTEST_VERSION=0.71.1
TERRAFORM_VERSION=1.17.2

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) platform=windows ext=.exe ;;
  Linux) platform=linux ext= ;;
  *) echo "unsupported OS $(uname -s): Linux and Windows on amd64 are pinned" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) ;;
  *) echo "unsupported CPU $(uname -m): only amd64 checksums are pinned" >&2; exit 1 ;;
esac

if [ "$platform" = windows ]; then
  OPA_ASSET=opa_windows_amd64.exe
  OPA_SHA256=4cd179b95041aa50c44241324da3becf35d0b28dca92bf10a07f32d002724d5e
  CONFTEST_ASSET=conftest_${CONFTEST_VERSION}_Windows_x86_64.zip
  CONFTEST_SHA256=34d623334b5e7ed4465bf62a4cb3b092684859cd3d224bbd390925a0852b922a
  TERRAFORM_ASSET=terraform_${TERRAFORM_VERSION}_windows_amd64.zip
  TERRAFORM_SHA256=2244b7a379ea8c4b224a2eab411b7288f41ef36316fca27ae4b51b1cf2a53024
else
  OPA_ASSET=opa_linux_amd64_static
  OPA_SHA256=35e3b352e715e80624ead6c89930d8585f6f7d94cdc409eb2a9fe36620dcccba
  CONFTEST_ASSET=conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz
  CONFTEST_SHA256=c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985
  TERRAFORM_ASSET=terraform_${TERRAFORM_VERSION}_linux_amd64.zip
  TERRAFORM_SHA256=e6f16b2f0b137ee5729caa8c4e79a3bae4ee261acd198a1fcfa8584a6296605b
fi

bin=.tmp/bin
dl=$bin/download
stamp="opa $OPA_VERSION, conftest $CONFTEST_VERSION, terraform $TERRAFORM_VERSION"

# fetch URL NAME: download one release asset over HTTPS (bounded retries and time) into the staging folder.
fetch() {
  curl -fsSL --retry 3 --connect-timeout 20 --max-time 600 --proto '=https' --tlsv1.2 -o "$dl/$2" "$1"
}

# verify NAME PINNED SUMS: the file must hash to the pinned value, which the published sums must list.
verify() {
  actual=$(sha256sum "$dl/$1" | cut -d' ' -f1)
  if [ "$actual" != "$2" ]; then
    echo "$1: sha256 $actual does not match the pinned $2" >&2
    exit 1
  fi
  if ! grep -Eq "^$2 [ *]?$1\$" "$dl/$3"; then
    echo "$1: the pinned sha256 is not listed in the published $3" >&2
    exit 1
  fi
  echo "verified $1 (sha256 $2)"
}

if [ -f "$bin/VERSIONS" ] && [ "$(cat "$bin/VERSIONS")" = "$stamp" ]; then
  echo "$stamp already in $bin"
  exit 0
fi

rm -rf "$bin"
mkdir -p "$dl"

gh=https://github.com/open-policy-agent
fetch "$gh/opa/releases/download/v$OPA_VERSION/$OPA_ASSET" "$OPA_ASSET"
fetch "$gh/opa/releases/download/v$OPA_VERSION/$OPA_ASSET.sha256" opa.sha256
verify "$OPA_ASSET" "$OPA_SHA256" opa.sha256
mv "$dl/$OPA_ASSET" "$bin/opa$ext"

fetch "$gh/conftest/releases/download/v$CONFTEST_VERSION/$CONFTEST_ASSET" "$CONFTEST_ASSET"
fetch "$gh/conftest/releases/download/v$CONFTEST_VERSION/checksums.txt" conftest.sums
verify "$CONFTEST_ASSET" "$CONFTEST_SHA256" conftest.sums
if [ "$platform" = windows ]; then
  unzip -o -q "$dl/$CONFTEST_ASSET" conftest.exe -d "$bin"
else
  tar -xzf "$dl/$CONFTEST_ASSET" -C "$bin" conftest
fi

hc=https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION
fetch "$hc/$TERRAFORM_ASSET" "$TERRAFORM_ASSET"
fetch "$hc/terraform_${TERRAFORM_VERSION}_SHA256SUMS" terraform.sums
verify "$TERRAFORM_ASSET" "$TERRAFORM_SHA256" terraform.sums
unzip -o -q "$dl/$TERRAFORM_ASSET" "terraform$ext" -d "$bin"

chmod +x "$bin/opa$ext" "$bin/conftest$ext" "$bin/terraform$ext"
rm -rf "$dl"
echo "$stamp" >"$bin/VERSIONS"
echo "installed $stamp into $bin"
