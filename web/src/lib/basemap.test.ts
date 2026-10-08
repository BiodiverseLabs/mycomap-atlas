import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import { BASEMAP_ATTRIBUTION, BASEMAP_URL } from "./basemap.ts";

// Every map's street layer comes from one place (lib/basemap.ts), so the tile
// provider, its credits and the privacy page can never disagree.
const src = join(import.meta.dirname, "..");

function sources(): string[] {
  return ["pages", "components"].flatMap((dir) =>
    readdirSync(join(src, dir))
      .filter((f) => f.endsWith(".tsx"))
      .map((f) => join(src, dir, f)),
  );
}

test("no page names a tile server of its own", () => {
  const offenders: string[] = [];
  for (const file of sources()) {
    readFileSync(file, "utf8").split("\n").forEach((line, i) => {
      if (/tile\.openstreetmap\.org|tiles\.stadiamaps\.com|\{z\}\/\{x\}\/\{y\}/.test(line)) {
        offenders.push(`${file}:${i + 1}: ${line.trim()}`);
      }
    });
  }
  assert.deepEqual(offenders, []);
});

test("every street layer uses the shared basemap and its credits", () => {
  const offenders: string[] = [];
  for (const file of sources()) {
    const text = readFileSync(file, "utf8");
    for (const match of text.matchAll(/<TileLayer\b[^>]*\/>/gs)) {
      const tag = match[0];
      if (!/url=\{BASEMAP_URL\}/.test(tag) || !/attribution=\{BASEMAP_ATTRIBUTION\}/.test(tag)) {
        offenders.push(`${file}: ${tag.replace(/\s+/g, " ")}`);
      }
    }
  }
  assert.deepEqual(offenders, []);
});

test("the tiles come from Stadia over https, with no key in the address", () => {
  assert.match(BASEMAP_URL, /^https:\/\/tiles\.stadiamaps\.com\//);
  assert.doesNotMatch(BASEMAP_URL, /api_key|key=|token/i);
});

test("the credits name Stadia Maps, OpenMapTiles and OpenStreetMap", () => {
  for (const credit of ["Stadia Maps", "OpenMapTiles", "OpenStreetMap"]) {
    assert.ok(BASEMAP_ATTRIBUTION.includes(credit), credit);
  }
});
