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
  const e = clone(FLOW_FIXTURE);
  e.steps.find((s) => s.id === "other_coarse")!.parts![0].id = "mystery";
  assert.equal(flowRows(e), null);
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
