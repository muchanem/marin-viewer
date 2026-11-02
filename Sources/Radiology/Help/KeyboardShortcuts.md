# Keyboard Shortcuts

Open this document from Help > Keyboard Shortcuts (⌘/). ⌘ means Command, ⌥ Option, ⌃ Control, and ⇧ Shift. Commands are available when their required repository, source file, semantic target, or selection exists. Menu items show availability.

## Repository and pull requests

**⌘O** — Open a repository folder.

**⌘P** — Open a pull request by number for the attached GitHub repository.

**⇧⌘P** — Import a Code Path from pasted text or a UTF-8 text file, then select Code Paths in the left sidebar.

**⌃⌘P** — Show Code Paths in the left sidebar, reopening the sidebar if collapsed.

**⌘R** — Reload the repository; during PR review, refresh the current PR.

**⌃⌘I** — Reindex the repository using its selected indexing personality.

**⌥⌘B** — Switch the current PR file between Before and After when both exist.

## Marin viewer

These apply while a prepared Marin PR is open in the viewer.

**⇧⌘O** — Open a prepared PR from the wordbase by number.

**⌘>** — Ask the PR session about the selection, or about the focused file, step, diagram box or note. The question's chip appears in the session panel. Right-click offers the same Ask item.

**⌥⌘3 / ⌥⌘4** — Show the PR By step / By file.

**⌥⌘I** — Show or hide the session panel, which takes the Context inspector's place.

**Escape**, with the PR map zoomed into a step diagram — Return to the PR map.

**⌘Return**, in the session panel — Send the question.

## Navigation and search

**⌘K** — Go to File. Type a fuzzy filename/path query; ↑/↓ selects a result, Return opens it, and Escape cancels.

**⌘T** — Go to Symbol using the semantic index. Type to filter, ↑/↓ selects a result, Return opens it, and Escape cancels.

**⌘L** — Go to a 1-based line in the current file. Return confirms; Escape cancels.

**⇧⌘F** — Search Repository and focus its query. Return in the query runs search; edits also update results.

**⌘F** — Show native Find in File.

**⌘G / ⇧⌘G** — Find next / previous match in the current file.

**⌘[ / ⌘]** — Navigate Back / Forward. Committed symbol, bookmark, and Code Path jumps preserve the exact departure caret and PR revision.

**⌃⌘J** — Go to the definition of the semantic symbol at the source caret.

**⌃⌘R** — Find references for the semantic symbol at the caret; pins these references in the inspector until Follow Caret is chosen.

**⌥⌘↓ / ⌥⌘↑** — Go to the next / previous changed block in the current PR file and revision; no wrap at the ends.

## Reader and presentation

**x**, with source focused and no modifiers — Expand/collapse the innermost named function's body at the caret. Expanding also opens folded ancestors. No action outside a foldable function. Holding the key does not repeatedly toggle.

Visiting a function automatically expands its body and folded ancestors. You can collapse it again with x; revisiting it expands it again.

**Return / keypad Enter**, with source focused and no modifiers — Go to the semantic definition at the caret or within the selected occurrence. Requires an available in-repository destination. ⌘[ returns to the exact departure caret.

**⌥⌘0** — Fold to Definitions.

**⇧⌘0** — Collapse Functions.

**⌥⌘1 / ⌥⌘2** — Normal Source / Critical Lens.

**⌃⌘O** — Toggle Source Files Only.

**⌃⌘T** — Toggle Hide Tests.

**⌘+ / ⌘−** — Increase / decrease source text size. On a US keyboard, + is Shift-=. Only the source font changes.

**⌃⌘S** — Toggle the left navigation sidebar (native Sidebar command).

**⌥⌘I** — Show/hide the right Context inspector, including recovery after dragging it closed.

## Bookmarks and Code Paths

**⌘D** — Bookmark/unbookmark the exact source caret location.

**⌘0 … ⌘9** — Open bookmark slots zero through nine, in saved list order. Dragging/reordering changes these assignments. Requires an assigned bookmark.

Code Paths is a left sidebar tab beside Files, Search, and (during PR review) Changes. Select another tab to switch away; saved traces and step selections remain. Bookmarks stays in the right inspector: hide it from its ellipsis menu and restore it using View > Context Panes > Bookmarks. Importing a Code Path preserves this preference. Conditional definitions have a source-variant menu.

**↑ / ↓**, with the Bookmarks or Code Paths list focused — Select a row using native list navigation.

**Return**, with Bookmarks or Code Paths focused — Open the selected bookmark or resolve the selected Code Path function in the current source revision. Code Paths use After during PR review.

**Delete**, with Bookmarks focused — Delete selected bookmarks using the list's native delete action. Code Paths are deleted through their actions menu.

## Inspector and sidebar focus

**↑ / ↓**, with References focused — Select a reference without committing a source jump.

**→ / ←**, with References focused — Expand/collapse the selected reference's source/caller context.

**Return**, with References focused — Open the selected reference or caller destination.

**Escape**, with References focused — Clear the selected reference.

**→ / ←**, with Definition focused — Expand/collapse definition details.

**Return**, with Definition focused — Open the available definition destination.

**↑ / ↓**, with Trait Implementations focused — Select an implementation.

**Return / Escape**, with Trait Implementations focused — Open the selected implementation / clear selection.

**↑ / ↓**, with Outline focused — Select/preview a declaration; **Return** commits it to navigation history. Native outline disclosures use →/←.

**← / →**, with the Files/Code Paths/Search/Changes tab strip focused — Select the previous/next tab, wrapping at the ends. Changes exists during PR review.

**↑ / ↓**, with Files or Changes focused — Move native list selection. **→ / ←** expands/collapses folders in Files. Native button activation uses Space; use Tab to reach controls.

## Sheets, text fields, and native macOS bindings

**Escape** — Cancel Go to File, Go to Symbol, Go to Line, Open Pull Request, or Import Code Path. Close Keyboard Shortcuts. In other focused inspector lists, Escape has the selection behavior described above.

**Return** — Confirm Go to File, Go to Symbol, Go to Line, or Open Pull Request. In Import Code Path's multiline editor, Return inserts a newline; activate the Import button to submit. Standard macOS default-button handling applies outside that editor.

**Tab / ⇧Tab** — Move keyboard focus forward/backward between eligible controls. **Space** activates a focused button or toggle; native menus and pickers support arrow navigation, Return, and Escape. macOS Keyboard Navigation settings determine which controls participate.

**⌘C / ⌘A** — Copy / select all in source and text controls. **⌘X / ⌘V**, **⌘Z / ⇧⌘Z** — Cut/paste and undo/redo in editable fields and the import editor. Source is read-only.

**← / → / ↑ / ↓** — Move the source/text caret. **⌥← / ⌥→** moves by word; **⌘← / ⌘→** moves to line boundaries; **⌘↑ / ⌘↓** moves to document boundaries. Add Shift to extend selection. macOS text controls also provide the system's standard Control-key text navigation and user-configured bindings.

**Page Up / Page Down**, **Home / End** — Native scrolling. Compact keyboards commonly use Fn-↑/↓ and Fn-←/→. In editable text, Delete removes backward, Fn-Delete removes forward, and Option-Delete removes the preceding word.

**⌘W / ⌘M / ⌘Q** — Close the reader window / minimize / quit.

**⌘H / ⌥⌘H** — Hide Marin Viewer / hide other apps.

**⌃⌘F** — Enter/exit full screen through the native Window command.

**⌘/** — Open this keyboard reference.

The lists above include every shortcut explicitly assigned by Marin Viewer, its focus-specific handlers, and common native macOS commands. System-wide shortcuts, menu remappings, text key-binding customizations, and accessibility settings follow macOS rather than an app-specific keymap. Actions such as Cancel Indexing, Exit PR, pane toggles, Copy/Delete Code Path, and bookmark reordering have menu/control access but no additional app-assigned shortcut.
