#!/bin/sh
set -eu

tool_root=$1
source_commit=$2
tool_version=$3
gradle_cli=$4
gradle_version=$5
mkdir -p "$tool_root"

if [ -z "$gradle_cli" ] || [ ! -x "$gradle_cli" ]; then
    echo "Downloading Gradle $gradle_version for Kotlin indexer installation…"
    archive="$tool_root/gradle.zip"
    /usr/bin/curl --fail --location --retry 2 --silent --show-error \
        "https://services.gradle.org/distributions/gradle-$gradle_version-bin.zip" -o "$archive"
    /usr/bin/curl --fail --location --retry 2 --silent --show-error \
        "https://services.gradle.org/distributions/gradle-$gradle_version-bin.zip.sha256" -o "$archive.sha256"
    expected=$(cat "$archive.sha256")
    actual=$(/usr/bin/shasum -a 256 "$archive")
    [ "${actual%% *}" = "$expected" ] || { echo 'Gradle download checksum mismatch.' >&2; exit 1; }
    /usr/bin/unzip -qo "$archive" -d "$tool_root"
    rm "$archive" "$archive.sha256"
    gradle_cli="$tool_root/gradle-$gradle_version/bin/gradle"
fi

echo "Downloading Kotlin SCIP compiler tooling at ${source_commit}…"
source_archive="$tool_root/source.tar.gz"
/usr/bin/curl --fail --location --retry 2 --silent --show-error \
    "https://github.com/scip-code/scip-java/archive/$source_commit.tar.gz" -o "$source_archive"
source_dir="$tool_root/source-$source_commit"
mkdir -p "$source_dir"
/usr/bin/tar -xzf "$source_archive" --strip-components=1 -C "$source_dir"
rm "$source_archive"

echo 'Building the pinned Kotlin SCIP indexer with JDK 17 or newer…'
"$gradle_cli" --project-dir "$source_dir" --no-daemon --no-configuration-cache \
    "-PreleaseVersion=$tool_version" :scip-java:installDist

distribution="$source_dir/scip-java/build/install/scip-java"
staging="$tool_root/distribution-next"
rm -rf "$staging"
/usr/bin/ditto "$distribution" "$staging"
/usr/bin/unzip -p "$staging/lib/scip-java-$tool_version.jar" scip-kotlinc.jar > "$staging/scip-kotlinc.jar"
/usr/bin/unzip -p "$staging/lib/scip-java-$tool_version.jar" scip-plugin.jar > "$staging/scip-plugin.jar"
"$staging/bin/scip-java" --version
rm -rf "$tool_root/distribution"
mv "$staging" "$tool_root/distribution"
rm -rf "$source_dir"
echo 'Kotlin semantic indexer installed.'
