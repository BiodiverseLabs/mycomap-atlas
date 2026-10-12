import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

// Public pages tell a visitor what is missing, never which command to run
// (release review s3). A command belongs in a DevHint, which only a
// development build shows, or on the Developers page.
const src = join(import.meta.dirname, "..");
const allowed = new Set(["Developers.tsx", "DevHint.tsx"]);

function pages(): string[] {
  return ["pages", "components"].flatMap((dir) =>
    readdirSync(join(src, dir))
      .filter((f) => f.endsWith(".tsx") && !allowed.has(f))
      .map((f) => join(src, dir, f)),
  );
}

test("no public page shows a visitor an ./atlas command", () => {
  const offenders: string[] = [];
  for (const file of pages()) {
    // A DevHint's command is for development builds only.
    const text = readFileSync(file, "utf8").replace(/<DevHint\b[^>]*\/>/gs, "");
    text.split("\n").forEach((line, i) => {
      if (line.includes("./atlas")) offenders.push(`${file}:${i + 1}: ${line.trim()}`);
    });
  }
  assert.deepEqual(offenders, []);
});

test("the check sees a command outside a DevHint", () => {
  const sample = 'Run <code>./atlas fit</code>. <DevHint command="./atlas api" />';
  assert.ok(sample.replace(/<DevHint\b[^>]*\/>/gs, "").includes("./atlas"));
  assert.ok(!'<DevHint command={`./atlas fit --taxon="${name}"`} />'.replace(/<DevHint\b[^>]*\/>/gs, "").includes("./atlas"));
});

test("no page tells a visitor a map failed its null test or has no habitat signal", () => {
  // Weak and failed maps both failed the shifted-null test; what tells them
  // apart is skill on held-out ground (lib/grade.ts). Comments may say so.
  const old = /failed its null test|no better than its null models|no habitat signal/i;
  const files = ["pages", "components", "lib"].flatMap((dir) =>
    readdirSync(join(src, dir))
      .filter((f) => /\.tsx?$/.test(f) && !f.endsWith(".test.ts"))
      .map((f) => join(src, dir, f)),
  );
  const offenders: string[] = [];
  for (const file of files) {
    const code = readFileSync(file, "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    code.split("\n").forEach((line, i) => {
      if (old.test(line)) offenders.push(`${file}:${i + 1}: ${line.trim()}`);
    });
  }
  assert.deepEqual(offenders, []);
});
