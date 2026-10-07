import { test } from "node:test";
import assert from "node:assert/strict";

import { reachedFromNote, renamedTaxonPath } from "./renamed.ts";

test("an old name's page goes to the name its records have now, saying where it came from", () => {
  const path = renamedTaxonPath("Mycena sp. 'IN10'", { name: "Mycena indianensis", how: "renamed" });
  assert.equal(path, "/taxa/Mycena%20indianensis?from=Mycena+sp.+%27IN10%27&how=renamed");
  const search = path!.split("?")[1];
  assert.equal(
    reachedFromNote("Mycena indianensis", search),
    "Formerly Mycena sp. 'IN10': these records were renamed on mycomap.org.",
  );
});

test("another spelling goes to the name in use, and says it is a spelling", () => {
  const path = renamedTaxonPath('Mycena "sp-IN10"', { name: "Mycena sp. 'IN10'", how: "spelling" });
  assert.ok(path);
  assert.equal(reachedFromNote("Mycena sp. 'IN10'", path!.split("?")[1]), 'Mycena "sp-IN10" is another spelling of this name.');
});

test("a current name, an unknown one, or a page reached directly stays put and says nothing", () => {
  assert.equal(renamedTaxonPath("Amanita muscaria", { name: "Amanita muscaria", how: "current" }), null);
  assert.equal(renamedTaxonPath("Nothing here", null), null);
  assert.equal(reachedFromNote("Amanita muscaria", ""), null);
  assert.equal(reachedFromNote("Amanita muscaria", "from=Amanita+muscaria"), null);
});
