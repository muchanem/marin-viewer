#!/bin/sh
set -eu

scip_cli=$1
output=$2
init_script=$3
compiler_jar=$4
javac_jar=$5
fallback_gradle=$6
shift 6

# The managed tool ships these beside its CLI. For an existing installDist
# installation, extract the exact embedded plugins from that CLI's own jar.
plugin_dir="$PWD/.radiology-index-tools"
mkdir -p "$plugin_dir"
if [ ! -f "$compiler_jar" ] || [ ! -f "$javac_jar" ]; then
    cli_dir=${scip_cli%/*}
    for jar in "$cli_dir"/../lib/scip-java-[0-9]*.jar; do
        [ -f "$jar" ] || continue
        /usr/bin/unzip -p "$jar" scip-kotlinc.jar > "$plugin_dir/scip-kotlinc.jar"
        /usr/bin/unzip -p "$jar" scip-plugin.jar > "$plugin_dir/scip-plugin.jar"
        compiler_jar="$plugin_dir/scip-kotlinc.jar"
        javac_jar="$plugin_dir/scip-plugin.jar"
        break
    done
fi
if [ ! -s "$compiler_jar" ] || [ ! -s "$javac_jar" ]; then
    echo 'The Kotlin SCIP compiler plugins are missing. Install the managed Kotlin indexer from the indexing status panel.' >&2
    exit 1
fi

if [ -x "$PWD/gradlew" ]; then
    gradle_cli="$PWD/gradlew"
elif [ -n "$fallback_gradle" ] && [ -x "$fallback_gradle" ]; then
    gradle_cli=$fallback_gradle
else
    echo 'This Gradle project has no executable wrapper and Gradle is not installed.' >&2
    exit 1
fi

target_root="$PWD/.radiology-scip"
rm -rf "$target_root"
mkdir -p "$target_root"
[ "$#" -gt 0 ] || set -- radiologyScipCompile
build_status=0
"$gradle_cli" --no-daemon --no-configuration-cache --no-build-cache --continue \
    --init-script "$init_script" \
    "-Dradiology.scip.kotlinc=$compiler_jar" \
    "-Dradiology.scip.javac=$javac_jar" \
    "-Dradiology.scip.sourceroot=$PWD" \
    "-Dradiology.scip.targetroot=$target_root" \
    -Pkotlin.compiler.execution.strategy=in-process "$@" || build_status=$?

# Preserve genuine compiler shards from independent successful projects after
# another project fails. The service marks this index Partial, including on
# later cache loads. Aggregation fails if there are no usable documents.
"$scip_cli" aggregate --output "$output" "$target_root"
if [ "$build_status" -ne 0 ]; then
    echo 'RADIOLOGY_KOTLIN_PARTIAL_BUILD: some Gradle compilation tasks failed; only compiler-produced documents are indexed.' >&2
fi
