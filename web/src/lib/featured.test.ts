import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { FEATURED_MAX, readFeatured, showFeatured } from "./featured.ts";

test("with no species chosen yet the slot hides itself", () => {
  assert.equal(showFeatured(readFeatured({ taxa: [] })), false);
  // A missing, broken or wrongly shaped file reads as no list, not an error.
  for (const bad of [undefined, null, "", 3, {}, { taxa: "Amanita muscaria" }, []]) {
    assert.deepEqual(readFeatured(bad), [], String(bad));
  }
});

test("the shipped list is valid and starts empty until the rebuild picks species", () => {
  const file = join(import.meta.dirname, "..", "..", "public", "featured.json");
  const json = JSON.parse(readFileSync(file, "utf8"));
  assert.ok(Array.isArray(json.taxa));
  assert.equal(showFeatured(readFeatured(json)), json.taxa.length > 0);
});

test("chosen species show, trimmed, without repeats, and never more than the slot holds", () => {
  const list = readFeatured({
    taxa: [
      " Amanita muscaria ",
      { name: "Laccaria laccata", note: " Ectomycorrhizal with many trees. " },
      "amanita muscaria",
      { name: "" },
      42,
      { note: "no name" },
      "Mycena sp. 'IN10'",
      "Trametes versicolor",
    ],
  });
  assert.equal(showFeatured(list), true);
  assert.equal(list.length, FEATURED_MAX);
  assert.deepEqual(list, [
    { name: "Amanita muscaria" },
    { name: "Laccaria laccata", note: "Ectomycorrhizal with many trees." },
    { name: "Mycena sp. 'IN10'" },
  ]);
});
