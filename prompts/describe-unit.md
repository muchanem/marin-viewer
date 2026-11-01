# Describe a unit of code

<!-- For the poller and the first-pass job. Claude and GLM-5.3 both run this prompt, and GLM-5.3 runs
it with no tools and no file access, so the rendered prompt must hold everything that the model needs. Fill
every {{placeholder}}; {{style}} takes the full text of prompts/style.md. Strip this comment. -->

You write descriptions of source files in the Marin repository (`marin-community/marin`) for a code
reader called the Marin viewer. This message holds everything you need. You have no tools, and you
cannot open files, so describe only what the text below shows.

The unit is `{{unit}}` at commit `{{commit}}`, in the package `{{package}}`. It is {{unit_kind}}: a
single directory, or a slice of a package small enough to fit here. Write an entry for every file
listed under `TARGETS`. The other files in the unit are there as context.

## Inputs

The inputs follow this prompt, each between a `=== BEGIN <name> ===` line and an `=== END <name> ===`
line:

1. `SOURCE <path>`: the full source of each file in the unit, one block per file. A sibling that does
   not fit the budget appears with its signatures only, and its block heading says so.
2. `README`: the package README.
3. `NEIGHBOURS`: for each module that the unit imports and each module that imports the unit, its path,
   its wordbase `l1` line or `no entry`, and the signatures of its classes and functions. A heading
   says whether the module is imported by the unit or imports it.
4. `SUBSYSTEM`: the subsystem page, or `none`.
5. `EXISTING`: the current entries for files in the unit, or `none` on a first pass. Each entry gives
   its commit, its layers and its symbols.
6. `DIFF`: on a regeneration, the diff of the targets from the last described commit to `{{commit}}`.
   On a first pass, `none`.
7. `TARGETS`: the paths to write entries for, one per line.

Use the neighbours to say who calls a file and what part it plays for them, by module and function
name. Do not describe the neighbours themselves, and claim nothing about them beyond their `l1` and
signatures. Use the README and the subsystem page for the package's terms and its purpose. Treat
existing entries as earlier drafts: keep what the source still supports and correct what it does not.

## Entries

Each entry describes its file as it is at `{{commit}}`. History, comparisons with earlier versions and
"now does" phrasing stay out of the entry.

- `l1`: one sentence about what the file does, usually starting with the action, as in "Runs a
  loopback HTTP listener inside a machine". A file that implements one half of a mechanism may start
  with a phrase that places it, as in "The guest half of the relay: ...".
- `l2`: one paragraph on the mechanism, with the main functions and types by their code names, the
  order of the calls, the callers in neighbouring modules, and limits and defaults with their values.
  Leave it out for a file under about 80 lines with an obvious mechanism.
- `l3`: a list of paragraphs, only for a file longer than about 500 lines or central to its package:
  secondary features, error handling, concurrency, and the callers that depend on particular behavior.
- `system`: the file's subsystem, normally the package name under `lib/`, such as `shellbox`.
- `symbols`: an item for each public function or class that other modules call, and for each private
  function that holds the file's main logic. Skip dunder methods, trivial accessors and helpers under
  about five lines. Give each symbol an `l1`, and an `l2` when its behavior under failure, cancellation
  or load needs explaining. Qualify a method with its class, as in `Task.close`.
- `changed_symbols`: on a regeneration, the symbols whose code the diff changes. Leave it out on a
  first pass.

Do not describe what a file lacks unless a caller would reasonably expect it.

On a regeneration, a file that the diff leaves unchanged keeps its existing entry unless the change
alters what the file does, for example when a function that it calls now behaves differently. Give such a
file `{ "keep": true }` in place of a new entry.

## Output

Reply with a single JSON object and nothing else: no Markdown fences, no commentary before or after
it. Its keys are exactly the paths listed under `TARGETS`, and each value is an entry or
`{ "keep": true }`. Give `keep` only to a target that has an entry under `EXISTING`. Escape double quotes and backslashes inside strings, and put code names in
backticks.

```json
{
  "lib/shellbox/src/shellbox/process_framing.py": {
    "l1": "...",
    "l2": "...",
    "system": "shellbox",
    "symbols": [{ "name": "FrameDecoder", "l1": "..." }]
  },
  "lib/shellbox/src/shellbox/task.py": {
    "l1": "...",
    "l2": "...",
    "l3": ["...", "..."],
    "system": "shellbox",
    "symbols": [{ "name": "Task.close", "l1": "...", "l2": "..." }],
    "changed_symbols": ["Task.close"]
  },
  "lib/shellbox/src/shellbox/image.py": { "keep": true }
}
```

Leave out `l2`, `l3`, a symbol's `l2` and `changed_symbols` when they would be empty. The poller writes
the entries, keeps each entry's `## Notes` section, and marks the notes about `changed_symbols` with
`(code changed at {{commit}})`.

## Examples

These file descriptions from the Marin viewer's demo of PR #10640 are at the right level.

`lib/shellbox/src/shellbox/process_framing.py`:

- l1: Encodes binary chunks of up to 64 KiB as one-letter-tagged base64 lines for transports that
  carry only text.
- l2: The module imports only the standard library because Daytona's bridge executes its source
  inside provider images that do not have Shellbox installed.

`lib/shellbox/src/shellbox/backends/local/cgroup.py`:

- l1: Creates a child cgroup per machine under a delegated cgroup v2 parent, kills it on close and
  removes it.

`lib/shellbox/src/shellbox/backends/local/transfers.py`:

- l1: Copies files between host and guest through tar streams while refusing symlinked destinations
  and guest-chosen names.

## Style

Write every text field under these rules.

{{style}}
