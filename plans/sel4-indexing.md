# seL4 compiler indexing

**Superseded workflow:** the app now has a persistent **seL4 indexing
personality** driven by editable TOML. Select it in Semantic Index; ordinary
Reindex then performs the full configuration union. The manual import and
Reindex limitation below describe the original indexing job. Use
[indexing personalities](indexing-personalities.md) for the current workflow.

The 2026-10-30 indexing job targets `/Users/tqbf/codebase/3p/seL4` (the
filesystem also accepts `sel4`), commit
`d419a119a61a9b42edf61fb79ad08de45248daa7`.
This is a prepared, local compiler index, not a new automatic seL4 build
adapter. The repository's tracked source bytes remain unchanged. Its only
intentional untracked artifact is `build/compile_commands.json`, which
Radiology discovers while hiding the build directory from Files.

## Why the default index was insufficient

The existing source-only Clang strategy tried all 180 C translation units,
but frequently stopped at missing `autoconf.h` and generated hardware/types
headers. Its normalized result was 379 documents, 9,808 symbols, 41,843
occurrences and 244 missing C/header paths out of 623 eligible paths. That
data remains in `/tmp/radiology-real-clang-fallback-cache/26bdbf971c10e23b`.
The first cold probe generated data but late queued compiler messages left
the status at Indexing; it was stopped. A cached reload completed in 0.254 s.
The service now ignores process progress after that strategy leaves Pending.

seL4's build concatenates C sources into `kernel_all.c`, using `#line`
directives. Clang's index describes physical file coordinates, so indexing
that generated concatenation would not give original-file navigation.
`scripts/prepare-sel4-index.py` uses the real, ordered upstream source list
to write a unity wrapper containing ordinary `#include` directives for the
original C files. Actual CMake flags, target triples and generated headers
are retained. No source is stripped, patched or expanded into the indexed
input. libsel4 gets its own public API consumer wrapper, using its actual
include paths and GNU C99 because its syscall headers use bare GNU `asm`.

Full source preprocessing for indexing was unnecessary. Upstream's required
header generation does preprocess bitfield specifications and a kernel
prune input. Only `kernel_headers`, `kernel_all_c_wrapper` and
`sel4_generated` are built; no kernel executable or fully expanded
`kernel_all.i`/`kernel_all_pp.c` indexing input is built.

## Configuration coverage and union

The final preparation contains all 41 checked-in verified presets plus 26
targeted variants: IA32, RISC-V32 on Spike, Allwinner A20, TK1/TX2 SMMUs,
x86-64 sysenter, MCS/non-MCS debug and four-core SMP across CPU families,
hardware debug, and utilisation/tracepoint/kernel-entry benchmarks.
All seven seL4 modes are represented: aarch32, aarch64, arm_hyp, ia32,
x86_64, riscv32 and riscv64. Each configuration has kernel and libsel4
translation units. Effective CMake values are recorded in `manifest.json`;
SMP is checked as enabled, rather than assuming requested flags took effect.
Fresh CMake configuration avoids cached disabled-option values.

Exploration caught two real setup issues. SMP requires one domain;
`KernelNumDomains=1` is necessary alongside `KernelMaxNumNodes=4`.
The upstream x86-64 tracepoint/entry-logging paths lack log-buffer
declarations, so those two benchmark variants use the supported IA32 ABI.
RISC-V32 requires a platform that supports it (Spike), rather than HiFive.

A single scip-clang run over the combined database drops some conditional
records in shared files. The non-MCS `invokeTCB_ThreadControl` definition
was a concrete failing check. `scripts/index-sel4.py` instead invokes the
pinned scip-clang 0.4.0 separately per configuration and unions the results
with `scripts/scip_union.py`. Unchanged occurrences are deduplicated;
configuration-specific definitions and actual compiler identities survive.
Local IDs are reconciled only by their compiler-reported definition ranges
in the same original document. Locals without definitions remain isolated
to their input index. Different coordinate encodings are rejected. Unknown
protobuf fields are preserved. No spelling-based references are added.

The union spans mutually exclusive build configurations. It can legitimately
offer several compiler identities/definitions at a location; the reader's
existing target-selection rules still apply. It is a broad browsing index,
not a claim that all variants coexist in one executable.

## Files and refresh recipe

Prepared builds, dependencies, logs, individual SCIP files, manifest, union,
provenance and coverage report live under:

`~/Library/Caches/Radiology/sel4-builds/`

The normal app cache is:

`~/Library/Caches/Radiology/repositories/26bdbf971c10e23b/`

Host prerequisites used here: CMake, Ninja, dtc, Homebrew LLVM 21.1.7,
the managed scip-clang 0.4.0 executable, and an isolated Python 3.11 venv
containing ply, PyYAML, Jinja2, lxml, typing_extensions, pyfdt and six.
Apple Clang lacks the required RISC-V target here, so use Homebrew LLVM.
Provision the Python dependencies only if recreating the environment:

```sh
python3 -m venv "$HOME/Library/Caches/Radiology/sel4-builds/venv"
"$HOME/Library/Caches/Radiology/sel4-builds/venv/bin/pip" install \
  ply pyyaml jinja2 lxml typing_extensions pyfdt six
```

From the Radiology root, regenerate and publish:

```sh
"$HOME/Library/Caches/Radiology/sel4-builds/venv/bin/python3" \
  scripts/prepare-sel4-index.py "$HOME/codebase/3p/seL4" \
  --output "$HOME/Library/Caches/Radiology/sel4-builds/matrix" \
  --clang /opt/homebrew/opt/llvm/bin/clang --all-verified --extended

python3 scripts/index-sel4.py \
  --prepared "$HOME/Library/Caches/Radiology/sel4-builds/matrix" \
  --indexer "$HOME/Library/Application Support/Radiology/tools/bin/scip-clang" \
  --output "$HOME/Library/Caches/Radiology/sel4-builds/matrix/union.scip"

mkdir -p "$HOME/codebase/3p/seL4/build"
cp "$HOME/Library/Caches/Radiology/sel4-builds/matrix/compile_commands.json" \
  "$HOME/codebase/3p/seL4/build/compile_commands.json"

RADIOLOGY_SEL4_PROBE_ROOT="$HOME/codebase/3p/seL4" \
RADIOLOGY_SEL4_APP_CACHE=1 \
RADIOLOGY_SEL4_PREBUILT_INDEX="$HOME/Library/Caches/Radiology/sel4-builds/matrix/union.scip" \
  swift test --no-parallel --filter Sel4IndexProbe
```

`PreparedClangIndexer` is acceptance tooling, not the shipped adapter. It
imports the verified union through the real SemanticIndexService; the cache
records the actual copy command. A fresh ordinary ScipClangIndexer actor must
then load that same cache without running the compiler. Standard Reindex still
runs the combined database and loses some configuration-specific records;
use the recipe above to retain maximal coverage. Regenerate after source or
configuration changes. Generated build inputs outside the repository are not
independently watched by the normal cache; preparation rewrites the database
and the import explicitly reindexes.

## Acceptance and remaining limits

Final accepted index: **598 documents,24,934 symbols,131,126 occurrences**,
all mapped to original source bytes; **177/177 build-backed physical C
files**. Of 623 eligible C/header paths, 25 remain un-emitted (eight are
symlink aliases). Source-only baseline: 379 documents and 41,843 occurrences.
The normal app cache contains the verified **8,382,025-byte** union, SHA-256
`93696286c72e28cc1497656442b6c47bbc9da0eb0b5b5f8979b229731a205dcb`.
Preparation/indexing report zero failed final profiles and zero compiler
errors across all 67 final runs.

The opt-in Sel4IndexProbe checks every published occurrence against the
original SourceBuffer, cross-source definitions/references for `schedule`,
`doIPCTransfer`, both TCB-control variants and `handleInterrupt`, SMMU/public
API definitions, all physical C files, unchanged source digests, and fresh
ordinary-service cache reuse. Python unit tests
check conditional union, deduplication, local identity separation and
reconciliation, undefined locals, and incompatible encoding rejection.

The final measured counts and validation logs are recorded in the newest
PROGRESS.md entry. Partial is intentional: not every header emits symbols,
symlink aliases are represented by physical targets, the orphan legacy
`src/machine/profiler.c` is not in the upstream build source lists, and
untested option combinations remain outside this finite matrix. Generated
headers outside the checkout do not become navigable source documents.
SwiftUI-pro was applied before and after the service change; macOS guidance
was reviewed. No views, typography, navigation controls or app session were
changed. Existing uncommitted project work was preserved; no merge was made.
