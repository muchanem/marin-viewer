# Reference caller trees and resizable Context sections

**Extended 2026-10-11:** [bookmarks.md](bookmarks.md) adds a third independently
scrolling Bookmarks pane using nested native splits. Both dividers are movable;
the two-pane layout described below records the initial caller-tree round.

Implemented 2026-10-11. Expanding a reference now shows its source context
followed by the containing callable and its incoming caller tree. The divider
between References and Definition/Outline is a native draggable `VSplitView`.
This supersedes the single outer scroll view and 320-point list budgets in
the 2026-10-08 inspector refinement; its type hierarchy and section tints remain.

## Tracing contract

`ReferenceCallTreeWorker` runs off MainActor. It reads each reference's source,
finds the innermost parsed callable, and links that callable's name to its exact
SCIP definition identity. Its incoming references must coincide with a parsed
call-name token resolved to that identity before traversal continues. There are
no spelling-based edges or Critical Lens policy filters. The first reference
may be any symbol use, including a variable/type use; the tree begins at the
callable containing it. A callable definition row starts at that callable.

Traversal is iterative depth-first, in deterministic file/line/column order.
Different call sites and paths remain separate, including shared ancestors.
Path-local semantic identity and canonical declaration-location sets stop
recursive branches before rendering a repeated callable, with a note on the
preceding row; unrelated branches remain. There is no fixed depth cutoff. Initial work returns up to
256 rows; **Trace more callers** increases the budget by 256 and retraces the
same deterministic prefix. Any remaining work is explicitly indicated by that
button. File data is bounded to 48 cached files within each request, and incoming
edges are reused within the traversal.

Closures belong to their own scope rather than their enclosing named function;
their invocation is an explicit boundary. Nested named functions own their
sites and can trace through their own indexed callers. Non-call references
(callbacks, aliases, imports) appear as boundaries with invocation unknown.
Unindexed callables, top-level uses, unsupported structure, unreadable files,
stale coordinates and parse errors are explicit. **No indexed callers** is a
leaf label, never proof of a runtime entry point. Dynamic dispatch, generated
code and unindexed configurations can leave additional paths outside this tree.

`ContextModel` starts work only on reference disclosure. Loaded trees survive
collapse/reopen within their reference identity. Collapse cancels pending work;
reference/repository/index/source invalidation cancels and clears trees.
Generation checks and cancellation prevent abandoned completions from landing.
Traversal file/edge caches are local to a request, never shared across roots.
Selection/disclosure never navigates. Caller buttons open the actual call site
through `AppModel.commitCaller` and existing semantic navigation, preserving
the departure caret for Back, including PR After navigation rules.

## Layout and typography

The upper pane contains the symbol heading and native reference List; the lower
pane contains a independently scrolling Definition or native Outline List.
References and Outline fill their pane rather than receiving fixed content
budgets. Native split panes have 150/100-point upper/lower minimum heights.
No custom drag gesture or separate source of divider state is introduced.

Each caller is a clickable capsule, colored by a deterministic hash of its
method name and full relative file path. The palette adapts to appearance and
the same pair retains its hue across branches and relaunches. See
[caller-pills.md](caller-pills.md) for colors and the cycle repair.
Caller names use existing semantic callout monospace semibold; filenames and
boundary notes use caption regular/secondary; line numbers use caption tabular
digits. The Callers label uses the existing caption semibold section style.
Branches indent by 12 points, capped at four levels to preserve narrow-column
space. Deeper rows include an explicit level marker. Full depth and path/line
remain in help and accessibility labels. Native buttons retain keyboard and
VoiceOver activation. Existing symbol title, definition-name deduplication,
source snippets, decorative section tints and Normal/Critical parity remain.

Applied swiftui-pro before code decisions and in the final review, plus
macos-design and typography-designer from `/Users/tqbf/.claude/skills/`.

## Validation

Latest validation after cycle repair and identity pills: **263 tests /55 suites**,
check/build/strict signing/resources and light/dark renders pass. See
[caller-pills.md](caller-pills.md). The figures below record the initial round.

Full Swift Testing run: **260 tests / 54 suites** passed. New checks cover
cross-file branching, a repeated ancestor on separate paths, UTF-16 columns
after emoji and accented names, nested functions, closure/callback boundaries,
self-recursion, missing files, stale coordinates, cancellation, lazy loading,
collapse/reopen caching, reset during work, and a 270-level tree continued past
the initial 256-row budget. AppModel integration verifies disclosure has no
navigation side effects and caller activation/Back preserves the exact caret.

The actual ContextInspectorView hosted in AppKit exposes a horizontal native
NSSplitView. Moving its divider from 350 to 230 points resizes both panes by
120 points and preserves selection, reference disclosure and definition
disclosure. SwiftUI adds a divider decoration subview; tests check the two
`arrangedSubviews`, not the raw subview count.

Six renders use actual ReferenceRow/ReferenceCallerRow components backed by the
branching index fixture at 220/280/420 points, light and dark. Artifacts:
`build/callers-review/{light,dark}-*.png`. To reproduce:

```sh
RADIOLOGY_CALLER_RENDER_DIR="$PWD/build/callers-review" swift test --filter ContextInspectorLayoutTests
```

Desktop automation could not start (`Sky Computer Use native pipe startup
failed`). Physical mouse dragging, live List scrolling and physical caller
clicks remain unverified. No user-reader restart or live repository interaction
was attempted. Logs: `/tmp/radiology-callers-{check,tests,integration,layout,build}.log`.

Compile and signed app build pass, strict deep codesign verification passes,
and the empty-environment `/tmp` resource probe loads all 8 grammars with 37
queries and 3 indexing scripts. Signed executable built **2026-10-11 13:31:01
CDT**. `git diff --check` passes. Work remains local/uncommitted.
