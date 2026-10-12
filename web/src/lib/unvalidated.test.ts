import { test } from "node:test";
import assert from "node:assert/strict";

import { notYetValidatedLine } from "./unvalidated.ts";

test("a taxon with records waiting for review says how many", () => {
  assert.equal(notYetValidatedLine(27), "Sequenced but not yet validated: 27");
  assert.equal(notYetValidatedLine(1234), "Sequenced but not yet validated: 1,234");
});

test("a taxon with none waiting shows no line", () => {
  assert.equal(notYetValidatedLine(0), null);
});

test("a server that has not counted them yet shows no line, not a zero", () => {
  assert.equal(notYetValidatedLine(undefined), null);
  assert.equal(notYetValidatedLine(null), null);
  assert.equal(notYetValidatedLine(Number.NaN), null);
});
