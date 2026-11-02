// TypeScript scan reader — 放射線
import type { Readable } from "node:stream";

export const MAX_SCANS = 10;

export interface Renderer {
  render(): string;
  readonly name: string;
}

export type Modality = "xray" | "ct";

export enum Level {
  Low = 1,
  High = 2,
}

export abstract class Base implements Renderer {
  protected count: number = 0;
  abstract render(): string;
  get name(): string {
    return "base";
  }
}

export class Scan extends Base {
  constructor(public title: string, private modality: Modality) {
    super();
  }

  render(): string {
    const parts: string[] = [this.title, this.modality];
    return parts.join(":");
  }
}

export namespace Helpers {
  export function normalize(value: string): string {
    return value.trim();
  }
}

export declare function external(input: unknown): asserts input is Scan;

const widen = <T,>(value: T): T[] => [value];
const cast = <string>(undefined as unknown);
