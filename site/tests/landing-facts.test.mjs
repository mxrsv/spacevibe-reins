// The landing copy against the app's own facts. No network.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), "utf8");
const contentSource = read("../components/landing/content.ts");
const activity = contentSource.slice(contentSource.indexOf("export const ACTIVITY"), contentSource.indexOf("export const TOKENS"));
const copy = read("../components/landing/directions/copy.ts");
const golden = JSON.parse(read("../../core/testdata/fixtures/golden/activity.json"));

test("example session titles mirror golden/activity.json", () => {
  const goldenTitles = new Set();
  const collect = (node) => {
    if (Array.isArray(node)) node.forEach(collect);
    else if (node && typeof node === "object") {
      if (typeof node.title === "string") goldenTitles.add(node.title);
      Object.values(node).forEach(collect);
    }
  };
  collect(golden);
  const siteTitles = [...activity.matchAll(/title: "([^"]*)"/g)].map((m) => m[1]);
  assert.ok(siteTitles.length >= 6, "the session rows were not found in content.ts");
  for (const title of siteTitles) assert.ok(goldenTitles.has(title), `"${title}" is not a title in golden/activity.json`);
  assert.ok(siteTitles.includes("2026-11-02 · pid 52003"));
});

test("Limits copy does not make the status line the source", () => {
  assert.doesNotMatch(copy, /status-line snapshot/i);
  assert.match(copy, /usage cache/);
});
