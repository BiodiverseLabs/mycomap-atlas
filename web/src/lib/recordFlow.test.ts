import { test } from "node:test";
import assert from "node:assert/strict";

import { distanceLabel, flowAddsUp, flowRows, type RecordFlowData } from "./recordFlow.ts";
import { FLOW_FIXTURE } from "./recordFlow.fixture.ts";

const clone = (d: RecordFlowData): RecordFlowData => JSON.parse(JSON.stringify(d));

test("every bar adds up: what is left after the last step is the records used", () => {
  assert.equal(flowAddsUp(FLOW_FIXTURE), true);
  const rows = flowRows(FLOW_FIXTURE)!;
  assert.equal(rows.at(-1)!.left, FLOW_FIXTURE.used);
  let left = FLOW_FIXTURE.total;
  for (const r of rows) {
    left -= r.removed;
    assert.equal(r.left, left, r.id);
  }
});

test("a flow that does not reach the records used is not drawn", () => {
  const d = clone(FLOW_FIXTURE);
  d.used += 46;
  assert.equal(flowAddsUp(d), false);
  assert.equal(flowRows(d), null);
});

test("a step whose reasons do not make its count is not drawn", () => {
  const d = clone(FLOW_FIXTURE);
  d.steps.find((s) => s.id === "name")!.parts!.pop();
  assert.equal(flowRows(d), null);
});

test("a step or reason this page cannot describe is not drawn", () => {
  const d = clone(FLOW_FIXTURE);
  d.steps.push({ id: "mystery", removed: 0 });
  assert.equal(flowRows(d), null);
  // A name reason the page has no words for.
  const e = clone(FLOW_FIXTURE);
  e.steps.find((s) => s.id === "name")!.parts![0].id = "mystery";
  assert.equal(flowRows(e), null);
  // Another source's remainder is named from its slug, but only a plain slug.
  const f = clone(FLOW_FIXTURE);
  f.steps.find((s) => s.id === "other_coarse")!.parts![0].id = "<b>source</b>";
  assert.equal(flowRows(f), null);
});

test("a negative count is not drawn", () => {
  const d = clone(FLOW_FIXTURE);
  d.steps[0].removed = -1;
  d.used += 1;
  assert.equal(flowRows(d), null);
});

test("the iNaturalist cutoff follows the pull's own setting", () => {
  assert.equal(distanceLabel(1000), "1 km");
  assert.equal(distanceLabel(2000), "2 km");
  assert.equal(distanceLabel(500), "500 m");
  const d = clone(FLOW_FIXTURE);
  d.max_accuracy_m = 2000;
  const why = flowRows(d)!.find((r) => r.id === "inat_coarse")!.why;
  assert.match(why, /more than 2 km, too loose for Atlas to trust which map cell it falls in/);
  assert.doesNotMatch(why, /5 km/);
});

test("every part the pull can send has words, and a remainder source is named from its slug", () => {
  const d = clone(FLOW_FIXTURE);
  const other = d.steps.find((s) => s.id === "other_coarse")!;
  other.parts!.push({ id: "mo_uncached", count: 1 }, { id: "mo_unexplained", count: 1 }, { id: "inaturalist", count: 2 });
  other.removed += 4;
  const name = d.steps.find((s) => s.id === "name")!;
  name.parts!.push({ id: "sequence_one_word", count: 1 }, { id: "rank_above_species", count: 1 });
  name.removed += 2;
  d.steps.push({ id: "other_kingdom", removed: 3 });
  d.used -= 9;
  const rows = flowRows(d)!;
  assert.ok(rows);
  const labels = rows.flatMap((r) => r.parts.map((p) => p.label));
  assert.ok(labels.includes("iNaturalist, changed while the pull ran"));
  assert.ok(labels.includes("sequence name is one word"));
  assert.equal(rows.at(-1)!.id, "other_kingdom");
  assert.equal(rows.at(-1)!.left, d.used);
});

test("a part of 0 is not listed, but still counts toward the sum", () => {
  const d = clone(FLOW_FIXTURE);
  d.steps.find((s) => s.id === "name")!.parts!.push({ id: "rank_above_species", count: 0 });
  const name = flowRows(d)!.find((r) => r.id === "name")!;
  assert.ok(!name.parts.some((p) => p.label === "named only above species level"));
});
