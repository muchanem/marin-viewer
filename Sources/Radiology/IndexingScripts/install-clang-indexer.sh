#!/bin/sh
set -eu

tool_bin=$1
tool_version=$2
expected_digest=$3
mkdir -p "$tool_bin"
staging=$(mktemp "$tool_bin/.scip-clang.XXXXXX")
trap 'rm -f "$staging"' EXIT HUP INT TERM

echo "Downloading scip-clang $tool_version for Apple Silicon…"
/usr/bin/curl --fail --location --retry 2 --silent --show-error \
    "https://github.com/sourcegraph/scip-clang/releases/download/v$tool_version/scip-clang-arm64-darwin" -o "$staging"
actual_digest=$(/usr/bin/shasum -a 256 "$staging")
[ "${actual_digest%% *}" = "$expected_digest" ] || { echo 'scip-clang download checksum mismatch.' >&2; exit 1; }
chmod 755 "$staging"
"$staging" --version
mv -f "$staging" "$tool_bin/scip-clang"
echo 'C/C++ semantic indexer installed.'
