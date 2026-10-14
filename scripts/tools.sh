#!/bin/sh
# Download the pinned OPA, conftest and Terraform releases into .tmp/bin. Each download must
# match the SHA-256 pinned below and the checksum file the project publishes for that release.
set -eu

OPA_VERSION=1.21.1
CONFTEST_VERSION=0.71.1
TERRAFORM_VERSION=1.16.5

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
  OPA_SHA256=25406f7c6e147d687fd7fd546f835bafa160a6242c605ee94a23ba6cd7bccdcd
  CONFTEST_ASSET=conftest_${CONFTEST_VERSION}_Windows_x86_64.zip
  CONFTEST_SHA256=34d623334b5e7ed4465bf62a4cb3b092684859cd3d224bbd390925a0852b922a
  TERRAFORM_ASSET=terraform_${TERRAFORM_VERSION}_windows_amd64.zip
  TERRAFORM_SHA256=01700102b7291f95c0ab61394b55bfd5f57a12ac65632c2c1958691c8cf438ef
else
  OPA_ASSET=opa_linux_amd64_static
  OPA_SHA256=668506eb17a2eaa1fce6cc0d1f42ef85125d4ac5bda5fc74d1152d0c77145031
  CONFTEST_ASSET=conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz
  CONFTEST_SHA256=c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985
  TERRAFORM_ASSET=terraform_${TERRAFORM_VERSION}_linux_amd64.zip
  TERRAFORM_SHA256=2bc2fcfff033265c9e02ca0351f01794eb122f62a9b2a49a3294b9e49eaab5e4
fi

bin=.tmp/bin
dl=$bin/download
stamp="opa $OPA_VERSION, conftest $CONFTEST_VERSION, terraform $TERRAFORM_VERSION"

# fetch URL NAME: download one release asset over HTTPS into the staging folder.
fetch() {
  curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$dl/$2" "$1"
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
