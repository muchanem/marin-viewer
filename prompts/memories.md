# Closing turn: memories

Mark has closed the session panel, started another session or closed the window. Look back over this
session and propose the notes that a later session should start with. Call `propose_notes` once, with
every note in a single list. Call it with an empty list when the session learned nothing of use to a later
session.

The viewer shows each proposed note with a discard ×. Mark drops unwanted notes, and the
rest are kept when he presses Done, opens another session or closes the window or the app. The
sidecar appends kept notes to the `## Notes` section of their entries and commits the wordbase.

## Contents of a note

A note records something that this session learned about the code, its history or how Mark reviews, which
a later session would otherwise have to work out again from the code or the review threads:

- how a piece of code behaves under a condition that the description leaves out, and the code that causes
  it;
- where a limit, default or decision comes from, with the file, PR or issue that sets it;
- the state of a design question at a commit, with the PR or issue that holds the discussion;
- a habit that Mark showed in this session's questions, such as the failure modes that he checks first.

## Exclusions

- Bugs, races, missing checks and other defects. They belong in draft review notes, which the
  session has already written with `draft_review_note`, or in Echo. Do not repeat them here.
- Facts that the entry's `l1`, `l2` or `l3` already states.
- A narration of the session, such as "In this session Mark asked about the relay."
- Mark's words. Report what he asked about, in your own sentences.
- Guesses. Record only facts that the session checked against the code or a cited source.
- Remarks about the viewer, the tools or the prompts.

## Fields

- `target`: the entry that receives the note.
  - A repository path, such as `lib/shellbox/src/shellbox/http_service.py`, for one file's behavior.
  - `path#symbol` for one function or class, such as `lib/shellbox/src/shellbox/task.py#Task.close`.
  - `system:<name>` for a fact across several files of a subsystem, such as `system:shellbox`.
  - `pr:<number>` for a fact about one PR's review.
  - `reviewer` for how Mark reviews.
- `text`: one to three sentences under `prompts/style.md`. Give code names in backticks.
- `commit`: the commit at which the note is true, normally the head that the session read. Put the short
  SHA in the text as well when the note describes code that may change, as in "the relay at 01a8bb8
  has no counters".

## Examples

These notes from the #10640 demo session are at the right level. Each one states a checked fact
with its source, and none of them repeats the bug that the session drafted as a review note.

Target `lib/shellbox/src/shellbox/http_service.py`:

> The relay's failure behavior under a stuck model endpoint comes from three limits defined in
> `http_service_guest.py` and imported by the host: 16 pending requests, 4 MiB bodies and a 600 s
> timeout. The guest starts its timeout when it emits a request and the host starts its own when the
> handler task begins, so the guest always gives up first.

Target `system:shellbox`:

> Relay throughput over cluster exec transports was the open design question in the #10640 review.
> #10118 records earlier incidents with the same kind of transport, and the relay at 01a8bb8 has no
> counters for requests running at once, queue depth or drops.

Target `reviewer`:

> On Shellbox changes you start from cancellation, teardown and failure under load, and you ask how
> a component behaves when a dependency hangs.

The session that wrote these also found that a client retry after the guest's 504 can end the
service. That finding went to a draft review note at `http_service.py:133` and appears in none of
the memories.
