# Code paths and keyboard help

Code paths are imported, ordered source traces supplied by agents or humans.
The **current format**, corrected by the user, is a freeform title on the first
line followed by **`file:function:description`**. There are no source line
numbers. Paths are repository-relative. The first two unescaped colons delimit
fields; escape colons as `\:` and backslashes as `\\` in filenames/function
selectors. Descriptions consume the rest of the line, including literal colons.
Blank lines after the title are ignored, fields are trimmed, LF/CRLF/CR and a
leading UTF-8 BOM are accepted. Imports validate atomically, with input-line
errors and a 2 MB limit. Same-title imports and repeated steps are retained.

## Workflow

Repository > Import Code Path… (⇧⌘P) accepts pasted text or a UTF-8 text file.
Successful import persists and selects the trace, closes the sheet, selects
**Code Paths** in the left navigation sidebar and reveals that sidebar if hidden.
Code Paths is a peer of **Files** and **Search**, with **Changes** also available
during PR review. **View > Show Code Paths** (⌃⌘P) selects/reveals it without
importing. Choose another tab to switch away; saved traces and step selections
remain. Sidebar mode follows the existing Files/Changes defaults on opening a
repository or PR; trace storage is unchanged.

Code Paths no longer participates in the right Context inspector or its Panes
menu. Bookmarks retains its independent persistent toggle, Hide Bookmarks action,
and View > Context Panes > Bookmarks recovery. Neither import nor selecting Code
Paths changes that preference or opens the right inspector. The retired
`contextPane.codePaths` preference is ignored; existing saved traces remain under
`repositoryCodePathsV1` and require no reimport.

The tab bar uses full titles when they fit and native SF Symbols at narrow widths
(including four-mode PR review at 220 points). Both layouts retain complete
accessibility labels, selection traits, tooltips and left/right arrow navigation.
Code Paths uses the normal sidebar background and native scrolling list; the
footer counts saved traces rather than files or source filters.

A picker selects among saved traces. Numbered steps show the function, wrapping
description and filename. Click or select and Return to resolve a step; Cmd-[
returns to the exact departure caret and PR revision. Plus imports another trace;
the actions menu copies the current trace in import format or deletes it.

Visiting a function opens its own body and any folded ancestors, including when
syntax arrives after the source loads. This applies to committed reader jumps
(Code Paths, definitions, bookmarks, outline commits and Back/Forward), while
sibling and nested functions retain their folds. Preview and ordinary UI
refreshes do not reopen a manually collapsed body; revisiting the function does.
The existing x key and gutter controls still toggle folding. The destination
caret survives late syntax highlighting and font updates.

## Persistence and symbol resolution

CodePathModel owns observable state. CodePathStore stores Codable records with
stable trace/step UUIDs in app UserDefaults (`repositoryCodePathsV1`), keyed by
canonical attached repository path. This follows bookmarks' app-managed storage,
without writing files into the browsed checkout. Checkout and PRs of that
attached repository share traces; a different checkout has independent traces.
Corrupt storage is visible and cannot be silently overwritten by import.

CodePathResolver loads readable source with SourceStore on an actor, validates
repository containment (including symlinks), parses the actual bytes with
SyntaxWorker and resolves a declaration with CodePathSymbolResolver. The current
open buffer is authoritative for a displayed file. Semantic indexing is not
required. In PR review it explicitly uses After; Before remains in Back history.
No line coordinate is saved, so inserted/deleted lines do not affect resolution.

Bare declaration names must identify a unique destination. Enclosing names using
`::` or `.` can disambiguate methods/modules; C++ out-of-class qualifiers are
recognized. An exact full declaration header, with whitespace normalized and
without its body/trailing semicolon, distinguishes overloads. Definitions win
over matching prototypes when structural function scopes establish a body.
Ordinary overload ambiguity produces an error. Definitions in mutually exclusive
preprocessor branches are alternatives for the same trace step: a click opens
the first in source order and a **N conditional definitions** menu selects the
others. This is source navigation, not a claim about the active build. Branch
checks ignore comments/strings and require opposing branches of a shared #if.

Assembly .S/.s/.asm files support explicit `name:` labels and standard declaration
macros BEGIN_FUNC, ENTRY, ENTRY_NP, SYM_FUNC_START and SYM_CODE_START. Comments,
strings, calls and END_FUNC are not destinations. For C/C++ parse errors caused
by configuration-dependent body braces, SyntaxWorker retains recognized function
declarator heads immediately followed by a body opener. These are used only for
named navigation; they do not invent a function extent for outline/folds/calls. Other unsupported
languages, missing/renamed functions, unreadable files and ambiguous labels fail
visibly without changing source/history. There is no arbitrary text-search
fallback through comments or string literals. Filename changes require an updated
trace; identities are names, not permanent semantic IDs across renames.

Async completions are cancelled/ignored after newer jumps, source navigation,
caret movement, trace changes, repository switches and PR refreshes.

## Help document and design

[KeyboardShortcuts.md](../Sources/Radiology/Help/KeyboardShortcuts.md) is the
complete user-facing keyboard reference and bundled single source of truth.
Help > Keyboard Shortcuts… (⌘/) opens a scrollable native sheet with semantic
headings and selectable text. It covers all authored command shortcuts and
focus-specific source/list/sheet handlers, plus common inherited macOS bindings.
The README links it. Navigation errors show their reason directly in the Code
Paths pane (up to five lines, with the complete reason in help/VoiceOver). Local/system keymap customization is explicitly distinguished
from app-assigned bindings. The stale Welcome ⌘P Go to File hint is corrected to
⌘K, matching the actual command.

Applied swiftui-pro before implementation and after review, macos-design and
typography-designer from /Users/tqbf/.claude/skills; used test-triage to separate
native layout assertions and the previously recorded PR-refresh timing flake.
Existing Theme fonts form the hierarchy: small semibold region title, native
picker, headline monospace function, body description, caption monospace secondary
path and callout step number. Descriptions explicitly remove List's inherited
one-line limit. Buttons/menus carry accessible labels; rows combine their step
number/function/description/path for VoiceOver. Dynamic system colors cover both
appearances. Import uses a multiline TextEditor with native paste and scrolling.
Enumerated rows use Array to retain macOS 14 compatibility.

[Generator skill prompt](code-path-generator-prompt.md) requires verified symbols,
explicit branch/uncertainty descriptions and the same three-field escape contract.
It is reusable prompt text, not an installed skill. Final validation and runtime
evidence are recorded in PROGRESS.md.


## seL4 acceptance (2026-10-31)

The user's exact 91-step ARM boot trace is a regression fixture at
Tests/RadiologyTests/Fixtures/code-paths/sel4-arm-boot.txt. Set
`RADIOLOGY_CODE_PATH_PROBE_ROOT=/path/to/seL4` when running CodePathRealDataProbe.
The d419a119a checkout reproduced 83/91 destinations before the repair and 91/91
afterward. A second probe runs all steps through AppModel, checks actual source
caret spelling and tests selecting conditional alternatives plus Back. Normal
runs need no external checkout. Native review opened the previously failing
entry macro, conditional functions and create_idle_thread; switch/hide/restore
and real relaunch were checked for the original inspector placement. The later
left-sidebar move supersedes those switch/hide controls. See newest PROGRESS.md
for current gates and limits.
