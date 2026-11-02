# Indexing personalities

The Semantic Index popover has a native **Personality** menu with **Default**
and **seL4**, plus **Show Settings File**. The choice persists per canonical
attached repository. PR snapshots use the attached repository's choice;
Before remains syntax-only. Changing the choice starts its index while
preserving the source, caret, history and view settings. Reindex, including
the existing keyboard command, always uses the selected personality.

This supersedes the manual-import/ordinary-Reindex caveat in the earlier
[seL4 indexing job](sel4-indexing.md). A combined compilation database alone
does not retain all conditional definitions. seL4 mode runs the separate
configuration compiler passes and unions their records on every Reindex.

## Editable settings

Templates ship in `Sources/Radiology/IndexingPersonalities/` and are installed
on first use to:

`~/Library/Application Support/Radiology/IndexingPersonalities/default.toml`

`~/Library/Application Support/Radiology/IndexingPersonalities/sel4.toml`

User edits are preserved across launches. Settings are reloaded on selection,
repository open/reload and Reindex. Invalid settings fail visibly without
falling back to another personality. Show Settings File remains available
when parsing fails. Root settings use single-line quoted strings, decimal
integers and string arrays (including multiline arrays/comments). The native
typed reader rejects unsupported root syntax, unknown root keys, duplicates,
bad identities and unsupported schema versions. The nested seL4 recipe uses
Python 3.11+'s standard TOML parser, `tomllib`.

| Root setting | Effect |
| --- | --- |
| `schema_version`, `id`, `engine` | Validate the selected personality and its pipeline |
| `name`, `summary` | Human-readable metadata and explanation |
| `indexers` | Default's adapter allowlist; empty means all registered adapters. seL4 requires `scip-sel4` |
| `project_limit` | Maximum detected project strategies, 1–256 |
| `clang_jobs` | Clang worker count, 1–64, including seL4's per-configuration compiler run |
| `bootstrap_python` | Ordered executable candidates for starting the seL4 runner; Default needs no Python |

`sel4.toml` contains the actual configuration matrix, not a flag selecting a
hardcoded matrix. All **67** profiles specify their name, upstream preset,
compiler triple and CMake definitions. The TOML also drives prerequisite
commands, required compiler targets, exact Python package pins and candidate
environments, upstream toolchain, generated-header targets, build concurrency,
unity source, public API headers, library source and GNU API dialect. The
profiles cover all 41 upstream verified presets plus 26 targeted variants
across all seven seL4 modes. Unsupported x86-64 logging variants use IA32;
SMP uses one domain and validates that CMake actually enables SMP.

## Execution and provenance

Default keeps normal project autodetection and Clang best-effort behavior.
seL4 uses `ScipSel4Indexer`, identified separately as `scip-sel4`, backed by
the same managed scip-clang 0.4.0 executable. Missing scip-clang uses the
existing Install action. The packaged Python runner requires Python 3.11+,
CMake, Ninja, dtc and a Clang with the configured targets (Homebrew LLVM here).
It checks configured Python environments against both imports and exact
package versions; if none match, it provisions an app-owned venv under
`~/Library/Application Support/Radiology/tools/sel4-python/`. Global Python
packages are untouched.

The full build/indexing pipeline runs against a disposable copy of the actual
repository inputs, including tracked build inputs hidden by Files. Internal
symlinks remain inside the copy. PR input provenance stays pinned to the
snapshot's Git blobs. Preparation, generated headers, compiler outputs and
Python caches do not write to the attached checkout. The copy is checked
before and after compilation; original input bytes are checked again before
publication. Only documents present in the source inventory are published.

Scripts live in the bundled `IndexingScripts` resource directory:

- `sel4_pipeline.py`: parses TOML, verifies/provisions tools, prepares and indexes
- `sel4_prepare.py`: configures the matrix, generates headers and writes original-source include wrappers
- `sel4_index.py`: runs each configuration separately and unions compiler records
- `sel4_sources.py`: inventories original checkouts and isolated source snapshots
- `sel4_scip_union.py`: deduplicates real records and preserves conditional/global/local identities

Legacy `scripts/prepare-sel4-index.py`, `scripts/index-sel4.py` and
`scripts/scip_union.py` forward to the bundled implementation. No second
hardcoded matrix remains in those scripts. Only upstream header generation's
required bitfield/prune preprocessing is performed; the index reads original
C sources through include wrappers rather than fully preprocessed kernel text.

Settings bytes are pinned beside each temporary compiler output, so editing
the user's TOML during a run cannot change what that run's digest describes.
The complete TOML and packaged pipeline bytes participate in strategy
identity, cache freshness and reuse. Reindex rereads the file and always
regenerates the selected pipeline. Cancellation uses existing process-group
termination and generation guards; temporary configuration, isolated inputs,
build artifacts and staging outputs are cleaned on completion/cancellation.
Bounded compiler/configure failure diagnostics remain in the status popover.

Default keeps its existing cache location. seL4 is isolated under
`<repository cache>/personalities/sel4/`, including inside a PR's flat revision
cache. Switching back to Default cannot overwrite seL4's union. Cached data
from another settings digest is not fresh or eligible for exact-byte reuse.

Partial remains an honest coverage label: symlink aliases, empty/include-only
headers, inactive options and the legacy profiler need not emit independent
documents. A finite configuration matrix does not prove exhaustive coverage.

## UI and validation

The picker is part of the existing status popover, directly below its heading.
It uses the native menu picker, existing Theme body/meta fonts, semantic
secondary text and native button styles. The main heading retains its weight;
the explanation and file action stay subordinate. No new font sizes, colors,
windows or onboarding flow are introduced. SwiftUI-pro, macOS and typography
guidance were applied before implementation and during final review.

`IndexingPersonalityTests` covers settings parsing/edit preservation, executable
worker settings, per-repository/PR identity, invalid-file failure, cancellation,
cache isolation, settings invalidation and ordinary cache reload.
`IndexingPersonalityUITests` exercises the model path used by the native picker
and Reindex action, checks reader/history preservation, and optionally renders
the production popover in light/dark mode with
`RADIOLOGY_PERSONALITY_RENDER_DIR`.

The opt-in `Sel4PersonalityProbe` runs the real app service against seL4,
checks source coordinates and conditional definitions, explicitly Reindexes,
and verifies fresh cached reload:

```sh
RADIOLOGY_SEL4_PERSONALITY_PROBE_ROOT="$HOME/codebase/3p/seL4" \
  swift test --no-parallel --filter Sel4PersonalityProbe
```

`RADIOLOGY_SEL4_PROBE_REINDEX=0` omits the second forced run for a cold/warm
check. Final measured results and known unrelated test limits are in the
newest PROGRESS.md entry.
