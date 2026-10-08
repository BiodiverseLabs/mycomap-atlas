import { test } from "node:test";
import assert from "node:assert/strict";

import { gradeNote, gradeVerdict, isFaint, mapGrade } from "./grade.ts";

test("only a map that passed shifted nulls is strong", () => {
  assert.equal(mapGrade({ skill: "passed", null: { design: "shift" } }), "strong");
  // A fit from before the switch passed scattered nulls only.
  assert.equal(mapGrade({ skill: "passed", null: { observed_auc: 0.8 } }), "weak");
  assert.equal(mapGrade({ skill: "passed" }), "weak");
});

test("a recorded grade is taken as it is", () => {
  assert.equal(mapGrade({ skill: "failed", grade: "weak" }), "weak");
  assert.equal(mapGrade({ skill: "passed", grade: "strong" }), "strong");
});

test("a map that did not pass is weak only with skill on held-out ground", () => {
  assert.equal(mapGrade({ skill: "failed", auc_mean: 0.66, boyce: 0.3 }), "weak");
  assert.equal(mapGrade({ skill: "failed", auc_mean: 0.66, boyce: -0.1 }), "failed");
  assert.equal(mapGrade({ skill: "failed", auc_mean: 0.49, boyce_mean: 0.3 }), "failed");
  assert.equal(mapGrade({ skill: "failed" }), "failed");
  assert.equal(mapGrade({ skill: "untested" }), "untested");
  assert.equal(mapGrade(null), "untested");
});

test("weak and failed maps are faint, and never told they have no habitat signal", () => {
  assert.equal(isFaint("strong"), false);
  assert.equal(isFaint("untested"), false);
  assert.equal(isFaint("weak"), true);
  assert.equal(isFaint("failed"), true);
  assert.match(gradeNote("weak") ?? "", /^Not shown to beat clustered collecting/);
  assert.match(gradeNote("failed") ?? "", /^Failed its null test/);
  assert.equal(gradeNote("strong"), null);
  for (const g of ["strong", "weak", "failed", "untested"] as const) {
    assert.doesNotMatch(`${gradeNote(g) ?? ""} ${gradeVerdict(g)}`, /no habitat signal/i);
  }
  assert.equal(gradeVerdict("weak"), "Not shown");
});
