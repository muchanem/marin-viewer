# Design and typography

The first version follows the macos-design, typography-designer, and swiftui-pro skills. The typography skill is available locally at `/Users/agentzero/.claude/skills/typography-designer/SKILL.md` even though it was absent from the initial Codex catalog.

## Layout

A caption semibold **Context** header keeps a labeled native **Panes** menu
available above the right inspector. Checked Toggles also live in View >
Context Panes; all-off presentation retains a headline empty-state title,
callout secondary explanation and native small Show All Panes button. Active
regions reclaim height through zero, one or two native dividers. Symbol titles
are retained when their former duplicate heading is hidden. See
[inspector-pane-controls.md](inspector-pane-controls.md).

Files follows explicit navigation and remount through native disclosure/List
selection/center scrolling. Passive caret/list browsing does not recenter. A
current Before-only path can be temporarily shown with caption regular/secondary
revision text; filter exceptions are named in the footer. See
[files-sidebar-navigation.md](files-sidebar-navigation.md).

**Current Context layout, 2026-10-11:** three independently scrolling panes:
References, Definition/Outline/Implementations and Bookmarks. Two nested native VSplitViews make
both horizontal dividers movable, with150/100/100-point minimum panes. Bookmarks
use a faint system-orange section tint, caption semibold header/PR scope, body
medium names, caption regular path/revision, and tabular ⌘0…⌘9 hints. Saved ordering
assigns the numbered shortcuts; source modes use ⌥⌘1/⌥⌘2. See [bookmarks.md](bookmarks.md).

Rust trait contexts use the middle pane for **Trait Implementations**. A caption
semibold header and compact count lead flat 22-point rows. Implementing types
are primary callout monospace semibold, with caption regular/tabular file:line
metadata inline. Full signatures/paths remain in help. Each full row is a native
plain Button; no trait subheading, file sections or disclosures add height.
Primary/secondary system text preserves hierarchy at widths from 220 to 420 points. A faint dynamic indigo
section tint uses the existing appearance-aware opacity. See
[rust-trait-implementations.md](rust-trait-implementations.md).

A native NavigationSplitView contains a resizable repository sidebar, the source surface, and the right-hand **Context inspector**. Two nested native VSplitViews separate symbol/References, Definition or Outline, and Bookmarks; all scroll independently, with draggable horizontal dividers. Expanded references include their containing callable's incoming caller tree. Exact symbol identity removes repeated Definition names. Faint system blue/teal/purple/neutral/orange backgrounds, headings and dividers distinguish sections. Caller names use semantic callout monospace semibold, with caption regular metadata and tabular line numbers; deep levels receive explicit markers when indentation is capped. See [bookmarks.md](bookmarks.md) for the current layout, [reference-call-trees.md](reference-call-trees.md) for caller behavior, and [inspector-refinement.md](inspector-refinement.md) for the retained hierarchy/contrast design. Use system window chrome, traffic lights, toolbar, lists, split views, open panel, and sheets. No simulated chrome, editor tabs, large dashboard cards, or decorative gradients.

Files and Search are sidebar modes. The toolbar holds back/forward, outline visibility, file lookup, repository search, and open. A quiet source header shows the relative path and Finder reveal; a footer shows language, line count, selected line, and read-only UTF-8 status. Empty states use ContentUnavailableView, with an actionable open button and recent folders on first launch.

## Typography specification

Caller entries now use native clickable capsules with a twelve-color dynamic
identity palette selected by a deterministic method-name/file-path hash.
Names retain callout monospace semibold; file metadata and line numbers retain
caption regular/tabular styles. Light/dark fill12%/24%, outline30%/50%; system
primary/secondary text preserves readability. See [caller-pills.md](caller-pills.md).

The source header gives the breadcrumb flexible leading space and change/
collapse tools a compact trailing area; Before/After sits beside the mode dropdown in the main toolbar. Path compaction keeps nearby
directories and enclosing declarations until they no longer fit, prioritizing
file/final declaration. It uses the existing semantic callout scale: secondary
regular context, primary regular file, primary medium final declaration. Full
location and declaration navigation remain in the ellipsis menu; the visible
Revision caption is hidden, with status retained in help/accessibility. Light/
dark five-width renders and native PR acceptance are recorded in
[source-breadcrumbs.md](source-breadcrumbs.md).

| Role | Family / style | Weight | Leading / usage |
| --- | --- | --- | --- |
| Native controls and file rows | System SF, semantic body | Regular | System leading; standard Mac density |
| Sheet and recent-folder headings | System SF, semantic headline | System emphasis | System leading; one level above body |
| Paths, counts, status, hints | System SF, semantic callout | Regular | Secondary foreground, never thin weight |
| Source breadcrumb | System SF, semantic callout | Regular context/file; medium final declaration | Secondary context, primary file/final declaration; one32-point row with compaction before truncation |
| Source and result previews | System monospace (SF Mono fallback) | Regular | Source starts at 14 pt with 22 pt line height |
| Line numbers | System tabular monospace digits | Regular | Source size minus 1; aligned to source line boxes |
| Main inspector symbol | System SF, semantic title3 | Semibold | Primary, up to two lines; caption kind/file:line beneath; dominant hierarchy |
| Context section labels | System SF, semantic caption | Semibold | Secondary References/Definition/Outline headings; status count secondary |
| Context signatures, reference rows, previews | System monospace, semantic callout | Regular; semibold for the match/emphasized line | Snippets on text background, 6 pt rounded separator stroke |
| Context snippet line numbers | System tabular digits, semantic caption | Regular | Secondary; source text primary for stronger contrast |
| Current-function shade | — | — | Full-width band over the caret's innermost function or method lines. `labelColor` at 3% (light) or 4.5% (dark). Bottom layer beneath the line tint, occurrences, pins, and caret. No border or text change |
| Receded source (Critical Lens) | Unchanged monospace, unchanged syntax color | Unchanged weight | Opacity 30 % (light) / 38 % (dark) for call-focused context: non-call source and ordinary calls recede; only parsed critical/unknown call-name tokens remain prominent. Supersedes protect-all-syntax rendering. De-emphasis is opacity, never weight or size; Normal restores full contrast and layout/coordinates stay untouched |
| Sidebar tabs | Native buttons with equal-width labels and selected underline | SF body regular/secondary; selected semibold/primary | Changes/Files/Search, no Browse caption; native focus, Left/Right and selected accessibility traits |
| Changes rows | Filename SF body; path/counts SF caption; modified M monospaced caption | Filename medium, selected semibold; details regular secondary | Two lines, min64-point right tabular count lane, 8% selected tint and2-point marker; native List selection |
| Source mode control | System menu picker in toolbar principal group, showing selected Normal/Critical beside Before/After; View menu ⌥⌘1/⌥⌘2 | Regular native body | New sessions start Normal; disabled without an open file |
| Critical call rows (hover only) | Name: body semibold; via chain and trailing location: callout secondary | — | One line per operation, with compact coverage status. No Critical sections or counts in the Context sidebar |
| Reachable-critical counts (source gutter only) | System tabular digits, 9 pt medium | Medium | Rounded square with accent stroke; proven zero/no body tertiary, `n+` partial and `–` no body. Hidden-line count stays in tooltip/accessibility. Sidebar outline counts removed |
| Critical hover popover | 380 pt wide, system popover, semitransient | — | Name/title and each indexed destination are whole-row buttons (body semibold, accent foreground); external rows are noninteractive. Native tracking covers padding and buttons, with a transit corridor and 700 ms exit grace; stable hosting survives loading updates. Opens after 350 ms dwell; outside click, key, scroll/context changes dismiss. Up to 8 concise rows; Reduce Motion honored |
| Source caret | — | — | 1.5 pt steady bar in the system's dynamic insertion-point color at 85% opacity, spanning the font's ascender to descender on the real baseline. No block, blink, or highlight. Shown only in the focused key-window reader with an empty selection, painted last in `drawBackground` (above line tint and occurrence/pin decorations) |
| Context one-line rows (concise default) | Name: body semibold; kind and trailing location: callout secondary; disclosure triangles: caption2 semibold secondary | — | One line per declaration, reference, or definition. Detail appears only on expansion. Statuses are one short line with the full reason as tooltip/accessibility. Region titles are "Declaration", "Definition", and "Outline" ("Under Caret" was removed as too explanatory). |
| Context availability detail and preview hint | System SF, semantic callout | Regular | Tertiary; e.g. "File not indexed", "Return opens · Esc clears" (Return first so truncation keeps it recognizable) |
| Canonical symbol IDs, indexer command lines, tool output | System monospace, semantic caption | Regular | Secondary foreground, selectable, truncated in the middle |
| Pull request menu and number sheet | System toolbar `Menu` with `arrow.triangle.pull`, inline picker rows `#724  Title · Open`; sheet headline + rounded number field like Go to Line | System | Label reads `#724` while reviewing, `Pull Request` otherwise; Title-and-icon label is visible; Exit PR is the first menu action while active/loading, Local Checkout the selected row outside review. Full title stays in Changes/menu/help; no PR subtitle in the toolbar |
| Changes list rows | Name: body; directory or `from old/path`: callout secondary; `+n −m`: callout tabular digits secondary; status symbol secondary (`plus.circle`, `pencil.circle`, `minus.circle`, `arrow.triangle.swap`, `doc.zipper` for binary) | Regular | Same row shape as the quick file picker; header line `#724 · Open · 11 files` with totals |
| Before / After control | Native segmented picker beside source-mode dropdown in toolbar principal group, 136-point width; status/rename details in help/accessibility | Regular native body | Disabled with explanatory help when only one revision exists; ⌥⌘B toggles |
| Changed-line marks | Gutter: 3-point bar at the gutter's trailing edge, `systemGreen`/`systemRed` at 60 %. Source: whole-line wash at 10 % light / 14 % dark, painted with the function shade beneath every other decoration | — | Green = added lines in After, red = removed lines in Before. Drawing only; text, layout, selection and copy unchanged |
| Changed-file and changed-callable dots | 6-point accent circle after the file name (tree) or before the `n L` count (outline) | — | Marks only files/callables that contain changed lines; directories stay quiet |
| Source filters | View menu toggles Source Files Only/Hide Tests, ⌃⌘O/⌃⌘T, plus Show All Files | System | Menu-only controls; footer names Source only/Tests hidden beside counts, with hidden-open-file notice. Empty lists retain Show All Files recovery |
| Hidden test region (source) | Header line keeps its syntax colors at the receded alpha; inline label system **regular**, source size − 3 pt (11 pt at default 14, min 10), secondary (tertiary when revealed) on a quaternary-label capsule, 12 pt after the header text | Regular | “Test code · N lines hidden” / “Hide test code”; proportional so it reads as interface, not code. Gutter reuses ▶ and the 9-pt medium tabular hidden-line capsule. Reader footer: `N test regions hidden` (inflected) or `Test file` label with `testtube.2`, callout secondary |
| Review footer | `Before · UTF-8 · Read Only` / `After · …`; semantic status `Not Indexed (Before)` with the explanation as help | callout secondary | Honest availability without new type roles |

All fonts and repeated metrics live in Theme. Code size is adjustable from 11–28 pt with the View menu and Cmd-plus/minus. Source leading is max(22, size × 1.55), keeping comfortable spacing as text enlarges. Source remains horizontally scrollable to preserve code indentation rather than imposing a prose measure. Native semantic fonts track system metrics. Body text and source use the system primary text colors; metadata uses secondary colors, and current-line tint is subdued. Background and label colors automatically adapt to light and dark appearances.

## Interaction and accessibility

| Shortcut | Action |
| --- | --- |
| Cmd-O | Open repository |
| Cmd-K | Go to file |
| Cmd-P | Open pull request by number |
| Opt-Cmd-B | Toggle Before/After for the open file of a review |
| Opt-Cmd-Down / Up | Next / previous change in the open file |
| Cmd-Shift-F | Repository search |
| Cmd-F | Native find within source, when source has focus |
| Cmd-G / Cmd-Shift-G | Next / previous in-file match |
| Cmd-L | Go to line |
| Cmd-[ / Cmd-] | Back / forward |
| Cmd-R | Reload repository and visible source |
| Cmd-plus / Cmd-minus | Source text size |
| Cmd-1 / Cmd-2 | Source mode Normal / Critical |
| Cmd-T | Go to symbol (semantic index) |
| Ctrl-Cmd-T | Hide Tests (Files tree and inline test code) |
| Ctrl-Cmd-O | Source Files Only (Files tree) |
| Ctrl-Cmd-J | Go to Definition at caret; Cmd-click an identifier does the same |
| Ctrl-Cmd-R | Find References at caret (also in the source context menu) |
| Ctrl-Cmd-I | Repository > Reindex; Cancel Indexing while running |

Icon buttons retain explicit text labels and shortcut help. The source exposes a read-only accessibility label, selection and copy use native text interactions, and lists/sheets use native keyboard focus. Finder folder drops open repositories. File reveal supplies the reverse connection to Finder. No custom motion is introduced, so reduced-motion preferences are respected without an animation branch.

The native inspector presents the current file's outline with all callables first, largest-to-smallest by source-line span, followed by a native non-callable declaration hierarchy. Names use existing body typography and system symbols, constrained to one line with middle truncation. Quiet trailing `n L` sizes use Theme.Fonts.meta (system callout), regular weight, secondary color and tabular digits, with full line-count help/accessibility. No extra context labels or Critical density badges are added. Syntax colours use Apple's dynamic system palette. The source footer reports language and parse status. The 72-point gutter shows only fifth-line numbers plus the actual caret line, using native small SF tabular digits (11 pt here), regular secondary and medium primary respectively, independent of source zoom. Restrained medium-weight disclosure markers occupy a 20-point full-line hit region. Collapsed functions add a three-point secondary-label logarithmic meter (6–16 points) and a distinct neutral capsule with the exact hidden-source-line count in 9-point medium tabular monospace. Counts use spare space beside sparse canonical numbers; if a count cannot fit, exact tooltip/accessibility text remains and the badge is omitted. Tooltip and accessibility help repeat the full count. Shape, length, and digits convey size without warning color. Hidden TextKit glyphs never receive stacked labels or nested meters; visible fragments retain their original source numbers. A compact semantic-callout breadcrumb row shows repository, path, and enclosing declarations. Cmd-K opens a compact native file-search sheet with immediate field focus, filename-first rows, a secondary relative directory, persistent keyboard selection, and an explicit result/refinement count.

Occurrence locks use four restrained dynamic system hues—teal, amber/orange,
violet, and rose—at translucent fills tuned separately for light and dark
appearance. A 1.4-point outline makes the locked state distinct from the plain
accent wash without relying on hue alone. Slots cycle for additional locks;
existing locks retain their assigned slot until removed. Text color, font,
selection, and layout are never changed. Source accessibility help reports the
number of locked groups and occurrences and explains the double-click toggle.

**Superseded 2026-10-04:** the Outline/Symbol switch was replaced by the two-region Context inspector; see plans/context-sidebar.md for its layout and type roles (region label subheadline semibold secondary; names body semibold; code callout monospaced with semibold emphasis; snippet numbers caption tabular tertiary). Historical description: the inspector gained a segmented Outline / Symbol switch. The Symbol pane is a restrained debug-grade card: name (semibold body), kind, canonical SCIP identifier (caption monospace, selectable), definition location, reference count, index state, then Find References results grouped by file with line numbers and monospace line text. The footer carries an unobtrusive index-state label with a system symbol (No Index, Indexing…, Index Current, Index Stale, Index Failed); clicking it opens a 440-point popover with the indexer, version, command line, exit status, bounded output, Reindex/Cancel, and an Install button when a managed tool is missing. ⌘-hover on a resolvable identifier underlines it in the accent color with a pointing hand; nothing appears where there is no in-repository target. Scope limits recorded at that time (historical; see below for the current distinction): source restoration was line-based; quick file lookup uses ordered-subsequence fuzzy matching and presents the best 100 results with a truthful total; ⌘T symbol ranking is exact > prefix > initials > subsequence and caps presentation at 200 symbols.

Current navigation semantics: reopening a file restores its last caret/viewport position. That restoration point mixes the caret and the viewport top. Semantic and sidebar jumps record the **exact caret byte** as the departure, so ⌘[ returns there precisely: Cmd-click, Go to Definition, reference commits, the definition link, and the declaration Line link. The Context regions follow only the genuine caret. Scrolling never changes them.
