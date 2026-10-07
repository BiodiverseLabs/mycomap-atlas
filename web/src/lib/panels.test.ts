import { test } from "node:test";
import assert from "node:assert/strict";

import { FULL_MODELS, MIDDLE_MODELS, SPARSE_MODELS, shownModels } from "./panels.ts";

const fitted = { auc_mean: 0.7 };

test("a taxon with 50 or more sites shows the three full models", () => {
  assert.deepEqual(shownModels({ maxnet: fitted, xgboost: fitted, rf: fitted }), FULL_MODELS);
});

test("a taxon with 20 to 49 sites shows the ensemble where the boosted trees were", () => {
  assert.deepEqual(shownModels({ maxnet: fitted, rf: fitted, esm: fitted }), MIDDLE_MODELS);
  assert.equal(MIDDLE_MODELS[1], "esm");
});

test("a taxon with 3 to 19 sites shows the ensemble alone", () => {
  assert.deepEqual(shownModels({ esm: fitted, maxnet: null, rf: null }), SPARSE_MODELS);
});

test("a taxon with no map yet, or still loading, keeps the three panels", () => {
  assert.deepEqual(shownModels({}), FULL_MODELS);
  assert.deepEqual(shownModels({ maxnet: undefined, esm: undefined }), FULL_MODELS);
});

test("a leftover ensemble beside boosted trees does not take a panel", () => {
  assert.deepEqual(shownModels({ maxnet: fitted, xgboost: fitted, rf: fitted, esm: fitted }), FULL_MODELS);
});
