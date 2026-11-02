// Prompt templates under `prompts/`: strip the leading HTML comment, fill `{{name}}` placeholders
// and fail on any placeholder left without a value.

import { readFile } from "node:fs/promises";
import path from "node:path";

export function fillTemplate(template: string, values: Record<string, string>, name = "template"): string {
  return template
    .replace(/<!--[\s\S]*?-->\s*/g, "")
    .replace(/\{\{(\w+)\}\}/g, (m, k: string) => {
      if (!(k in values)) throw new Error(`${name} has a placeholder ${m} with no value`);
      return values[k]!;
    })
    .trim();
}

export async function renderPrompt(promptsDir: string, file: string, values: Record<string, string>): Promise<string> {
  const template = await readFile(path.join(promptsDir, file), "utf8");
  const needsStyle = template.includes("{{style}}");
  const style = needsStyle ? (await readFile(path.join(promptsDir, "style.md"), "utf8")).trim() : "";
  return fillTemplate(template, needsStyle ? { style, ...values } : values, file);
}

/** One input block, in the `=== BEGIN <name> ===` form the prompts describe. */
export const inputBlock = (name: string, body: string) => `=== BEGIN ${name} ===\n${body.trimEnd()}\n=== END ${name} ===\n`;
