# Style rules for wordbase text

These rules apply to everything that the viewer's agents write for Mark: file and subsystem
descriptions, PR descriptions, code-path steps, review notes and memories. They combine section 3 of
the Mariven code-style gist with Marin's `docs/dev-guide/writing-style/ai-writing-donts.md`. The
examples at the end come from the demo's hand-written descriptions, which Mark accepted as the
standard.

After generation, `sidecar/src/lint.ts` checks the mechanical rules. A description that still fails
after one rewrite is kept with a `lint:` field listing the hits. Lint covers a small part of these
rules, so a clean lint result says little about the prose.

## Layers

Every description comes in up to three layers. The viewer shows `l1` and collapses the others.

- `l1` is a single sentence. For a file, it says what the file does, usually starting with the action
  (`Runs a loopback HTTP listener ...`). For a step or a PR, it says what happens or what the change
  lets a caller do.
- `l2` is a paragraph of two to five sentences. It gives the mechanism: the functions and types by
  their code names, the order of the calls, the data passed between them and the limits that matter.
- `l3` is a list of paragraphs for large or central code: secondary features, limits and their
  values, scope, related PRs and review history.

Each layer adds facts that the earlier ones lack. Do not restate `l1` in `l2`. Leave a layer out when the
code gives it nothing to say; most small files need only `l1`.

## Technique

Descriptions narrate operations on data. A reader should be able to follow a value from the caller
through each function to its result.

- Narrate the operations carried out on data in place of stating invariants between data structures.
  An introduction that says what something is stays as it is: `This machine washes dogs` is fine.
- Make agents perform actions: a caller, a function, a process, the host, the guest. Abstractions do
  not act.
- Show with deixis, scope and context: give the function, the file, the limit and its value.
- Use asyndeton over polysyndeton, and hypotaxis over parataxis. Subordinate the clause that depends
  on the other.
- Avoid restrictive relative clauses where a prepositional phrase or a second sentence works, and
  never drop the relative pronoun (`A body the check refuses`).
- Encode structure typographically. Break a tangled sequence into a numbered or indented list in
  place of one long sentence.

## Voice

Write plain, idiomatic American English in the present tense. Keep normal word order, with the subject
first.

- State what is true at the described commit. History belongs in `l3` of a PR or in a note, with a commit or PR number.
- Do not editorialize. Check each sentence for spin and remove it.
- Do not refer to conversation context that a later reader lacks, and never quote Mark.
- Do not give small behavior changes undue weight. Watch for suspiciously specific denials such as
  `{present behavior}, not {past behavior}` or `{past behavior} is avoided`.
- Use no first-person pronouns. PR descriptions and notes may address Mark as "you" when they report
  his review history.
- Use one term for each object, and keep the code's own name for it.

## Patterns to avoid

Overconfident and universal claims: `under these conditions, {this} is exactly {that}`, `the
{this} *is* the {that}`, and claims about a `fundamental insight` or `deepest lesson`.

Advertising patterns:

1. Counting openers: `Three interfaces, one underlying structure`, `One migration: ...`,
   `Two structures:`.
2. Cliffhangers: `Two findings, and one of them's worse than it looks.`
3. Rhetorical formulas: `The A *is* the B`, `C does D, never E`, `F is a G, H is an I, J is a K`.
4. Announcing the structure of what follows in place of saying it. Start the list.
5. Signposts: `and this is the part that actually matters`, `Here's the thing`, `That last point
   matters here`, `The real question is X`, `What you actually care about is X`, `The distinction
   worth keeping straight:`.
6. Opening labels: `Straight answer:`, `Short version:`.
7. Bridge prose, importance claims and stage directions: `The main change is...`, `Stepping
   back...`, `Importantly`, `It is worth noting`, `In this section...`, `Let's dive in`.
8. Generic conclusions, recaps and sign-offs: `In conclusion`, `To summarize`.

Stock contrast, from Marin's guide: `X, not Y`, `not X, but Y`, `not just X, but also Y`, `more than
X`, `the question is no longer X; it is Y`, `the real story is X`, `what matters is X`, `It's not X.
It's Y`, and `rather than Y` when no real comparison is being made. State X directly, and split a
real comparison into plain claims:

- Bad: `The issue is not query execution, but the metadata path.`
- Better: `Metadata loading takes 12 seconds. Query execution takes 400 ms.`

Grammatical negation is fine when the negative fact matters: `The ablation has not run.`

Negative ontologies: `it does this, never that`, `this happens here, and that happens nowhere`, `it
does this, and does not do that`, `this does not do what nobody asked for`.

Formulaic balance: `Not only X, but also Y`, `While X is true, it is important to note...`.

Headings that begin with a question word, and question words at the head of a phrase.

Em dashes, en dashes, decorative Unicode and emoji. Make an aside its own sentence or delete it.

Bold labels, takeaway boxes and decorative headings.

Synonym rotation, adjective trios and the reflexive rule of three when two items matter. Heavy use of
semicolons to attach small clauses.

### Banned words

The gist bans these as overstretched jargon or metaphor, in every inflection:
`artifact`, `bring up`, `buy`, `contract`, `earn`, `flight`, `footgun`, `golden`, `hug`,
`hydration`, `inflight`, `land`, `mint`, `name (v.)`, `noun`, `own (v.)`, `pin`,
`plumbing`, `preflight`, `provenance`, `reach`, `runbook`, `seam`, `see`, `shape`, `ship`, `sit`,
`smoke`, `speak`, `sugar`, `surface`, `touch`, `triage`, `verb`, `want`, `weld`, `wire`.
Entries marked `(v.)` are banned in that sense only, so `its own cgroup` and `the container names`
are fine.

Never write `honest`, `genuine`, `fair`, `pushback`, `today` or `tomorrow`.

Marin's guide adds `Additionally`, `Furthermore`, `Moreover`, `Notably`, `landscape`, `ecosystem`,
`interplay`, `tapestry`, `testament`, `delve`, `showcase`, `underscore` and `foster`. Delete
`robust`, `powerful`, `seamless`, `significant`, `crucial` and `pivotal` unless a measured result
follows.

Code names in backticks are exempt: `own_cleanup` and `see_also` are identifiers.

## Backwards English

Agents produce a kind of word salad that the gist calls Backwards English. Purge it completely. Its
marks:

1. Nominalized processes as subjects: `Picking generates the...`, `The code knows...`.
2. Periodic sentences that hold the subject back until the end.
3. Abstractions as agents: `A trigger names no moment...`. Words such as `earns`, `buys`, `sees`,
   `reaches`, `knows`, `owns`, `names`, `speaks`, `touches`, `sits`, `wants` and `has` invite this,
   which is why most of them are banned.
4. Wrong word forms: `the metadata, which was ornament` for `ornamentation`.
5. Comma chains without a connector: `(username, avatar, signature, privacy)`.
6. Bipartite statements joined with `, and`: `Every enabled attempt gets tested, and a match
   enqueues a job`. Join two clauses this way only when the second action follows the first in the
   same process, as in the examples below. Otherwise subordinate one clause or write two sentences.
7. Inverted word order, with the object first: `A body the check refuses...`, `One pass names the column no fold
   sees`.
8. Fragments joined haphazardly to avoid a semicolon: `This does that, and the thing does not affect
   that`.
9. Odd numerals: `One database that is served`, `Fetches one provided URL`. Use an article wherever
   an article works.
10. Question words opening phrases or statements: `The process names what touches one record`,
    `What touches one record:`.
11. Negative ontologies, inlined counterfactuals and conditional moods: `A body that passes this check
    holds nothing a column would refuse.`
12. Garden-path sentences, where the end of the sentence overturns the obvious parse of its start.

To fix Backwards English, rewrite the sentence from scratch. Rearranging its words, chopping it into
staccato fragments or swapping synonyms leaves prose just as bad. No find-and-replace fixes these
rules.

## Evidence

- Give the code path, configuration, issue, measurement or unknown behind each claim.
- Replace adjectives with numbers and named facts.
- Say `we have not tested X` when evidence is missing.
- Keep the text consistent with the code at the described commit, and remove explanations that the code
  no longer supports.

Score every paragraph. Each one must carry a concrete result, setup, decision, constraint or caveat.
Ask of every sentence:

1. What information disappears if it is deleted?
2. Can a number, a named fact, a decision or an explicit unknown replace it?
3. Does it still describe the current code?
4. Could it appear unchanged in a random software announcement?

Delete sentences that fail. A shorter accurate description beats a longer one.

## Cold reader

Subsystem pages and PR descriptions also go to a fresh session that receives only the description
and the code. It lists the terms, referents and claims that it cannot check against the code. Fix each
gap with the smallest local edit, and narrow a claim when its full explanation would interrupt the
text.

## Examples

These are the demo's descriptions for PR #10640, quoted exactly. Match their density and register.

### File entry, `lib/shellbox/src/shellbox/task.py`

l1: Describes a task as named containers with endpoints and readiness probes, and closes the
containers together.

l2: `TaskSpec.__post_init__` rejects duplicate names, a missing primary, mixed network policies and
repeated ports, since every member binds on the same loopback. `Task.close` memoizes one closing
future, so concurrent callers wait on the same teardown.

### File entry, `lib/shellbox/src/shellbox/process_session.py`

l1: Gives every backend the same persistent pipe session, with serialized reads and writes, a bounded
stderr tail and teardown that finishes even when the caller is cancelled.

l2: Backends pass four callables (a reader, write, wait and stop). `own_cleanup` keeps cleanup tasks
in a module-level set so the event loop cannot drop them, and `await_cleanup` waits for them before
re-raising the caller's cancellation.

### File entry, `lib/shellbox/src/shellbox/http_service_guest.py`

l1: The guest half of the relay: a standard-library HTTP server that turns each request into a JSON
line on stdout and waits for the matching response on stdin.

l2: A non-blocking semaphore admits 16 requests at once and drops further connections without a
response. Each handler thread waits at most `REQUEST_TIMEOUT` (600 s) and then answers 504.

### Code-path step 6, "Relay HTTP to the host"

l1: `serve_http` starts the guest listener, and `_pump` forwards each request to the host handler and
writes the response back.

l2: A handler exception becomes a generic 502 body, which keeps provider error text and headers on
the host. When the helper exits while the `async with` body runs, the done callback cancels the body,
and cleanup replaces that cancellation with the helper's own error.

### Code-path step 7, "Tear down"

l1: Cleanup runs in tasks held in a module-level set, so a caller cancelled twice still waits for
cleanup before its cancellation propagates.

l2: `finish_owned` loops on `asyncio.shield` until the owned task finishes, swallowing the caller's
cancellations, and returns or raises the owned task's result. Callers re-raise their original error
afterwards.

### PR description, #10640

l1: Shellbox can start a task as a group of named containers on one private loopback network, and a
handler on the host can answer HTTP requests made inside a sandbox that has no external network.

l2: A caller lists containers in a `TaskSpec` and marks one as primary; the single-machine `create`
call now builds a one-container task through the same path. The local backend starts each member
under bubblewrap, puts every member after the primary into the primary's network namespace, and
writes the container names into each member's `/etc/hosts`. Backends gain a persistent process
session with binary stdin and stdout: local and Docker use subprocess pipes, and Daytona carries
base64 lines over its command-log websocket. `serve_http` runs a small standard-library listener in
the primary and relays each request over that session to a trusted handler on the host, so model and
judge credentials stay out of the sandbox.
