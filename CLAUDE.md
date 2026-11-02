* Keep a master PLAN.md as an index to the documentation you make for this codebase.

* Store specific in-depth documentation in plans/whatever.md.

* Record progress in PROGRESS.md. I should be able to tell a future agent "read PLAN.md and
PROGRESS.md" and trust it's up to speed with this codebase.

* Before and after deciding on code, use the swiftui-pro skill to ensure we're following
  modern best practices.

* When setting type, use the typography-designer skill to make sure we're using consistent
  type scales with a sensible visual hierarchy. Pay attention to type weight and emphasis.

* Use the macos-design skill to make sure the UI we come up with makes sense as a modern
  macOS app, with modern professional macOS idioms. Keep things simple.

* You may push PRs, but you MUST NOT ever merge them youself to main.

* Do every UI capture and every interactive check of the running app on the built-in Retina
  display, never on the external ultrawide. The ultrawide is 1x, which halves the detail, and
  Mark's other work is open there, so windows on it are often covered. Use
  `tools/viewer-ui.swift`: `launch`, then `place` (moves the window to the Retina screen), then
  `press`, `keys`, `dump` and `capture`. `capture` refuses a window that is not on the Retina
  screen. Offscreen `cacheDisplay` snapshots are fine in tests but don't count as UI review.
