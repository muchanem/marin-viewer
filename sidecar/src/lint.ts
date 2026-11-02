// Style lint for generated descriptions (DESIGN.md section 8).
//
// The rules come from prompts/style.md: the Mariven code-style gist (section 3) and Marin's
// docs/dev-guide/writing-style/ai-writing-donts.md. Text inside backticks and fenced code blocks is
// masked before matching, so identifiers such as `own_cleanup` or `see_also` never fire.
//
// lint() reports; it never rewrites. The generation pass rewrites a failing description once and then
// keeps it with a `lint:` field listing the hits that remain.

export interface LintHit {
  rule: string;
  match: string;
  index: number;
}

/** Replace code spans with spaces of the same length, so indices still point into the original text. */
function mask(text: string): string {
  const blank = (s: string) => s.replace(/[^\n]/g, " ");
  return text
    .replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[ \t]*$/gm, blank)
    .replace(/(`+)(?:(?!\n[ \t]*\n)[^`])+?\1/g, blank);
}

const words = (list: string[]) => list.map((w) => w.replace(/ /g, "\\s+")).join("|");

// The gist's list of overstretched jargon and metaphor, then "honest, genuine, fair, pushback, today,
// tomorrow". Verbs carry their inflections: the gist bans "sees", "reaches" and "touches" by name.
// `name` and `own` are banned only as verbs and get their own rules below.
const BANNED: string[] = [
  "artifact", "artifacts",
  "bring up", "brings up", "bringing up", "brought up",
  "buy", "buys", "buying", "bought",
  "contract", "contracts",
  "earn", "earns", "earned", "earning",
  "flight", "flights",
  "footgun", "footguns",
  "golden",
  "hug", "hugs", "hugged", "hugging",
  "hydration",
  "inflight", "in-flight",
  "land", "lands", "landed", "landing",
  "mint", "mints", "minted", "minting",
  "noun", "nouns",
  "pin", "pins", "pinned", "pinning",
  "plumbing",
  "preflight",
  "provenance",
  "reach", "reaches", "reached", "reaching",
  "runbook", "runbooks",
  "seam", "seams",
  "see", "sees", "seen", "saw", "seeing",
  "shape", "shapes", "shaped", "shaping",
  "ship", "ships", "shipped", "shipping",
  "sit", "sits", "sat", "sitting",
  "smoke",
  "speak", "speaks", "spoke", "spoken", "speaking",
  "sugar",
  "surface", "surfaces", "surfaced", "surfacing",
  "touch", "touches", "touched", "touching",
  "triage", "triaged", "triaging",
  "verb", "verbs",
  "want", "wants", "wanted", "wanting",
  "weld", "welds", "welded",
  "wire", "wires", "wired", "wiring",
  "honest", "honestly", "genuine", "genuinely", "fair", "pushback", "today", "tomorrow",
];

// Marin's "Avoid LLM cadence" and "Require evidence" lists.
const CADENCE: string[] = [
  "additionally", "furthermore", "moreover",
  "landscape", "ecosystem", "interplay", "tapestry", "testament",
  "delve", "delves", "delving", "showcase", "showcases", "underscore", "underscores", "foster", "fosters",
  "robust", "powerful", "seamless", "seamlessly", "significant", "significantly", "crucial", "pivotal",
];

const DETERMINER = "the|a|an|its|their|his|her|our|your|my|every|each|this|that|these|those|which|what|no|any|all|some|both";
const POSSESSIVE = "my|your|his|her|its|our|their|one's|[A-Za-z_]+'s|[A-Za-z_]+s'";
const NUMBER = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|several|a few|a couple of";

// A comparison that licenses "rather than": a comparative word or a number in the same sentence.
const COMPARISON = /\b(?:prefer\w*|more|less|fewer|faster|slower|cheaper|costlier|larger|smaller|bigger|shorter|longer|better|worse|higher|lower|earlier|later)\b|\d/i;

interface Rule {
  rule: string;
  pattern: RegExp;
  /** Capture group whose start is the reported index; defaults to the whole match. */
  group?: number;
  /** Return false to drop a match. */
  keep?: (match: RegExpExecArray, text: string) => boolean;
}

const SIGNPOSTS = [
  "here's the thing", "here is the thing",
  "the (?:part|thing|bit) that (?:actually |really )?matters",
  "that last point matters",
  "the real (?:question|issue|problem|story|point|answer) is",
  "what (?:you |we |really |actually )*(?:care about|matters) (?:most )?is",
  "worth keeping straight",
  "(?:it is |it's )?worth noting",
  "importantly", "notably",
  "the key (?:point|insight|takeaway|thing|idea) (?:is|here)",
  "fundamental insight", "deepest lesson",
  "the main change is",
  "stepping back",
  "what this means is",
  "let's dive in", "let us dive in",
  "here is a summary", "here's a summary",
  "in this section",
  "in conclusion", "to summarize", "in summary",
  "short version", "straight answer", "long story short", "the bottom line", "tl;dr",
  "the question is no longer",
];

const RULES: Rule[] = [
  { rule: "dash", pattern: /[—–]|(?<=\s)--(?=\s)/g },
  { rule: "banned-word", pattern: new RegExp(`(?<![\\w'-])(?:${words(BANNED)})(?![\\w'-])`, "gi") },
  {
    // "name" as a verb: followed by a determiner and not itself the head of a noun phrase.
    rule: "banned-word",
    pattern: new RegExp(`(?<!\\b(?:${DETERMINER}|same|full|file|container|endpoint|host|user|field)\\s+)\\b(?:name|names|named|naming)\\s+(?=(?:${DETERMINER})\\b)`, "gi"),
  },
  {
    // "own" as a verb. "its own cgroup" is an adjective; "the loop owns the task" is the banned use.
    rule: "banned-word",
    pattern: new RegExp(`\\b(?:owns|owning|owned\\s+by)\\b|(?<!\\b(?:${POSSESSIVE})\\s+)\\bown\\b(?!_)`, "gi"),
  },
  { rule: "cadence-word", pattern: new RegExp(`(?<![\\w-])(?:${words(CADENCE)})(?![\\w-])`, "gi") },
  { rule: "stock-contrast", pattern: /,\s+not\s+(?!only\b|just\b|yet\b)[a-z]/gi },
  { rule: "stock-contrast", pattern: /\bnot\s+(?:just|only|merely|simply)\b/gi },
  { rule: "stock-contrast", pattern: /\bnot\b[^.;:!?\n]{1,80},\s*but\b/gi },
  { rule: "stock-contrast", pattern: /\b(?:it|this|that)(?:'s|\s+is)\s+not\b[^.!?\n]{1,80}[.!?]\s+(?:it|this|that)(?:'s|\s+is)\b/gi },
  { rule: "stock-contrast", pattern: /\bmore than\s+(?:just\s+)?(?:a|an)\b/gi },
  {
    rule: "stock-contrast",
    pattern: /\brather than\b/gi,
    keep: (m, text) => {
      const start = Math.max(text.lastIndexOf(".", m.index), text.lastIndexOf("\n", m.index)) + 1;
      const stop = text.slice(m.index).search(/[.!?\n]/);
      const sentence = text.slice(start, stop < 0 ? undefined : m.index + stop);
      return !COMPARISON.test(sentence.replace(/rather than/i, ""));
    },
  },
  {
    // "Three interfaces, one structure", "Two structures:", "One migration: ...".
    rule: "counting-opener",
    pattern: new RegExp(`(^|[.!?]["')\\]]?\\s+|\\n[ \\t]*(?:[-*+][ \\t]+|#+[ \\t]+)?)((?:${NUMBER})\\b[^.!?:\\n]{0,60}?(?::|,\\s*(?:and\\s+)?(?:${NUMBER}|a single)\\b))`, "gi"),
    group: 2,
  },
  { rule: "signpost", pattern: new RegExp(`\\b(?:${SIGNPOSTS.join("|")})\\b`, "gi") },
  {
    // Opening labels such as "Short version:" or "Answer:" at the start of a line or text.
    rule: "signpost",
    pattern: /(^|\n)[ \t]*((?:summary|answer|verdict|bottom line|short answer|takeaway|key takeaway|net|result)\s*:)/gi,
    group: 2,
  },
  { rule: "question-heading", pattern: /^#{1,6}[ \t]+(?:what|why|how|when|where|which|who|whose|whom)\b[^\n]*/gim },
  { rule: "bold-label", pattern: /\*\*[^*\n]{1,80}?:\*\*|\*\*[^*\n]{1,80}?\*\*[ \t]*:|__[^_\n]{1,80}?:__/g },
];

export function lint(text: string): LintHit[] {
  const masked = mask(text);
  const hits: LintHit[] = [];
  const seen = new Set<string>();
  for (const { rule, pattern, group, keep } of RULES) {
    pattern.lastIndex = 0;
    for (let m = pattern.exec(masked); m; m = pattern.exec(masked)) {
      if (m[0].length === 0) {
        pattern.lastIndex++;
        continue;
      }
      if (keep && !keep(m, masked)) continue;
      const part = group ? (m[group] ?? "") : m[0];
      const offset = group ? m.index + m[0].indexOf(part) : m.index;
      const length = part.length;
      const key = `${rule}:${offset}`;
      if (seen.has(key)) continue;
      seen.add(key);
      hits.push({ rule, match: text.slice(offset, offset + length).trim(), index: offset });
    }
  }
  return hits.sort((a, b) => a.index - b.index || a.rule.localeCompare(b.rule));
}
