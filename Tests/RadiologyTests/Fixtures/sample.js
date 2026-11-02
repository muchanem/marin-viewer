// Scan reader — 放射線
import { useState } from "react";

export const MAX_SCANS = 10;
const defaultTitle = "胸部";

export class Scan {
  #secret = 1;
  static kind = "scan";

  constructor(title) {
    this.title = title;
  }

  render() {
    return `${this.title}:${this.#secret}`;
  }
}

export function load(path) {
  const parts = path.split("/");
  for (const part of parts) {
    console.log(part);
  }
  return new Scan(parts.at(-1) ?? defaultTitle);
}

const double = (x) => x * 2;

const obj = { title: defaultTitle, render: function () { return 1; }, go: () => 2 };
