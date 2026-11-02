// Token counts for prompt budgets: OpenAI's o200k_base encoding through js-tiktoken. OpenRouter does
// not publish GPT-6.1 Terra's tokenizer, so o200k is a proxy; the comparison checks it against the
// `prompt_tokens` OpenRouter returns.

import { Tiktoken } from "js-tiktoken/lite";
import o200k from "js-tiktoken/ranks/o200k_base";

let encoder: Tiktoken | null = null;

export type TokenCounter = (text: string) => number;

/** o200k_base tokens in `text`, with special-token text counted as ordinary text. */
export const countTokens: TokenCounter = (text) => {
  encoder ??= new Tiktoken(o200k);
  return encoder.encode(text, [], []).length;
};
