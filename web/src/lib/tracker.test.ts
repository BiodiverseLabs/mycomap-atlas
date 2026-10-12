import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { gradeLabel, homeLine, newFindsLine, percent, schemeRows, type Tracker, type TrackerRow } from "./tracker.ts";

const row = (over: Partial<TrackerRow>): TrackerRow => ({
  scheme: "shift", release: "all", grade: "strong", subset: "new_site", places: 40, finds: 44, ranked: 36,
  top_half: 0.64, top_half_ci: [0.48, 0.78], top_tenth: 0.19, top_tenth_ci: [0.1, 0.35], mean_rank: 0.6,
  mean_rank_p: 0.01, top_tenth_p: 0.04, beats_effort: 0.57, beats_effort_n: 36, outside_aoa: 0.05,
  beyond_reach: 0.05, aoa: "known", boyce: null, boyce_effort: null, ...over,
});

const tracking = (over: Partial<Tracker> = {}): Tracker => ({
  grid: "draft", status: "tracking", since: "2026-10-03", rows: [], taxa: [],
  headline: { scheme: "shift", grade: "strong", subset: "new_site", places: 40, ranked: 36, top_half: 0.64,
    top_half_chance: 0.5, beats_effort: 0.57, effort_chance: 0.5 },
  ...over,
});

test("the Home line counts new sites against chance, and waits until there is a share", () => {
  assert.equal(
    homeLine(tracking()),
    "36 new sites found since 3 October 2026, scored on strong maps made before they were found: 64% landed in the top half of their map, against 50% by chance.",
  );
  assert.equal(homeLine(tracking({ headline: { ...tracking().headline!, top_half: null } })), null);
  assert.equal(homeLine({ grid: "draft", status: "not_started", since: "2026-10-03", rows: [], taxa: [] }), null);
  assert.equal(homeLine(undefined), null);
  assert.match(homeLine(tracking({ headline: { ...tracking().headline!, scheme: "skill" } }))!, /passed their test/);
});

test("the taxon line says only 'fewer than 5' when the server withholds the count", () => {
  assert.equal(newFindsLine({ since: "2026-10-08", finds_text: "fewer than 5" }), "New finds since this map was made: fewer than 5");
  assert.equal(newFindsLine({ since: "2026-10-08", finds: 12, finds_text: "12", top_half: 9 }),
    "New finds since this map was made: 12, 9 in its top half");
  assert.equal(newFindsLine(undefined), null);
});

test("a withheld share is a dash, never 0%", () => {
  assert.equal(percent(null), "—");
  assert.equal(percent(0), "0%");
  assert.equal(percent(0.666), "67%");
});

test("old-scheme grades are not called strong, and a map is never said to have failed its null test", () => {
  assert.equal(gradeLabel("skill", "passed"), "Passed (old test)");
  assert.equal(gradeLabel("skill", "failed"), "Did not pass");
  assert.equal(gradeLabel("shift", "strong"), "Strong");
});

test("a scheme's table keeps its grades in order and leaves out per-release rows", () => {
  const t = tracking({ rows: [row({ grade: "weak" }), row({ grade: "strong" }), row({ grade: "any" }),
    row({ release: "R1", subset: "all" }), row({ scheme: "skill", grade: "passed" })] });
  const rows = schemeRows(t, "shift", ["new_site"]);
  assert.deepEqual(rows.map((r) => r.grade), ["any", "strong", "weak"]);
});

test("the site never asks for the private ledger or any record of a find", () => {
  const files = ["lib/api.ts", "lib/tracker.ts", "pages/Home.tsx", "pages/Methods.tsx", "pages/Taxon.tsx"];
  for (const file of files) {
    const text = readFileSync(join(import.meta.dirname, "..", file), "utf8");
    assert.doesNotMatch(text, /ledger|private\/tracker|observation_id/, file);
  }
});
