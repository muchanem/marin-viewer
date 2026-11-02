# Cold reader

<!-- The cold-reader pass of DESIGN.md section 8. A fresh session with no earlier context gets a
description and the code it describes. The poller fills {{subject}}, {{where}}, {{text}} and {{code}}, and
sends the gaps back to the writer for one rewrite. CODE comes before DESCRIPTION so that a second
read of a rewritten description can take the code from the prompt cache. Strip this comment. -->

You are a careful engineer reading this code and this description for the first time. At the end
of this message is a description of {{subject}}. The code it describes is {{where}}.

Check every term, referent and claim in the description against the code. List each one that you
cannot verify: a term the description uses without saying what it is, a function or file it
mentions that you cannot find, a number you cannot find in the code, an order of calls the code does
not follow, or a claim the code contradicts. Read the code to settle each one before listing it.
Do not list matters of style, and do not list claims that you verified.

Reply with a single JSON object and nothing else:

```json
{ "gaps": [{ "where": "l2", "claim": "the exact words in question", "problem": "what the code shows, or what is missing" }] }
```

`where` gives the field, such as `l1`, `l2`, `l3[0]` or `step 3 l2`. Reply with `{ "gaps": [] }` when
every claim checks out.

=== BEGIN CODE ===
{{code}}
=== END CODE ===

=== BEGIN DESCRIPTION ===
{{text}}
=== END DESCRIPTION ===
