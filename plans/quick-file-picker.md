# Quick file picker

Cmd-K opens Radiology's compact native Go to File sheet. Cmd-P opens a pull request by number.
The search field receives focus immediately. Up/Down changes the active result
without leaving the field, Return opens it through the normal history-aware file
navigation path, Escape cancels, and pointer activation opens the clicked row.
Dismissal returns keyboard focus to the source reader.

## Matching and ranking

Search uses the repository discovery snapshot directly, so it is available
without SCIP or ripgrep. Matching is case- and diacritic-insensitive ordered
subsequence matching across filenames and relative paths. Thus `engrs` matches
`engine-foo.rs`, while out-of-order characters do not. Ranking is deterministic:

1. exact filename;
2. filename prefix;
3. contiguous filename substring;
4. gappy filename subsequence;
5. relative-path-only subsequence.

Within a tier, punctuation/path and camel-case boundaries, smaller gaps, shorter
paths, then stable localized path ordering break ties. Filename is primary row
text and its relative directory is secondary text for disambiguation.

## Performance and lifecycle

Matching runs away from the main actor, yields and observes cancellation every
128 files, and keeps only the best 100 candidates using bounded insertion rather
than sorting every match. A repository/query identity guards publication, so an
old task cannot repaint a changed query or repository. The footer reports the
full match count and says to refine when only the best 100 are visible. Empty
queries show a bounded initial repository ordering; empty repositories and no
matches have native empty states.

Opening a result calls the same `AppModel.openFile` route as the file tree. It
therefore preserves navigation history, default folds, syntax/semantic loading,
and stale occurrence clearing. The picker does not depend on or alter the source
buffer.

## Verification

Tests cover `engrs` to `engine-foo.rs`, rank tiers, relative-path matching,
case/diacritic folding, out-of-order rejection, deterministic 100-result bounds
with truthful totals, and selection reset/clamping. Native validation on the
real tkos repository found 6,721 files for the empty query and ranked
`engine/rust/src/app_image.rs` first for `apimgrs`, displaying its relative
directory and 89 total fuzzy matches. Keyboard focus remained in the field while
selection moved; Return opened the selected file and restored source focus.
