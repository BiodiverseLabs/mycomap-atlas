import { test } from "node:test";
import assert from "node:assert/strict";

import { REACH_KM, openingView } from "./mapView.ts";

// The coloured ground of Rhodotus reticeps: five collections from Missouri to
// Quebec, on a raster that covers the world.
const rhodotus = [
  { lat: 37.1, lng: -92.3 },
  { lat: 36.8, lng: -90.9 },
  { lat: 38.0, lng: -86.5 },
  { lat: 37.7, lng: -86.2 },
  { lat: 46.1, lng: -73.2 },
];
const world = { south: -60, west: -180, north: 85, east: 180 };

const kmPerDegree = 111.32;

test("a map opens on its collections, not on the whole raster", () => {
  const [[south, west], [north, east]] = openingView(rhodotus, world)!;
  // Comfortably within the continent: nothing like the 145° x 360° raster.
  assert.ok(north - south < 25, `spans ${north - south}° of latitude`);
  assert.ok(east - west < 45, `spans ${east - west}° of longitude`);
});

test("every collection sits inside the opening view with the colour's full reach around it", () => {
  const [[south, west], [north, east]] = openingView(rhodotus, world)!;
  const reach = REACH_KM / kmPerDegree;
  for (const p of rhodotus) {
    assert.ok(p.lat - south >= reach - 1e-9 && north - p.lat >= reach - 1e-9, `lat ${p.lat}`);
    // A degree of longitude is shorter than one of latitude away from the equator.
    assert.ok(p.lng - west >= reach && east - p.lng >= reach, `lng ${p.lng}`);
  }
});

test("a single collection still gets a region around it, not a point", () => {
  const [[south, west], [north, east]] = openingView([{ lat: 40, lng: -100 }])!;
  assert.ok(north - south > 8);
  assert.ok(east - west > 8);
});

test("the view stays inside the raster, where all the colour is", () => {
  const raster = { south: 35, west: -95, north: 50, east: -70 };
  const [[south, west], [north, east]] = openingView(rhodotus, raster)!;
  assert.deepEqual([south, west, north, east], [35, -95, 50, -70]);
});

test("a raster that misses the collections does not move the view off them", () => {
  const elsewhere = { south: -40, west: 100, north: -10, east: 150 };
  const [[south, west], [north, east]] = openingView(rhodotus, elsewhere)!;
  assert.ok(south < 37 && north > 46 && west < -92 && east > -73);
});

test("with no collections the map opens on its raster, and with neither it stays put", () => {
  assert.deepEqual(openingView([], world), [[-60, -180], [85, 180]]);
  assert.equal(openingView([], null), null);
  assert.equal(openingView([{ lat: Number.NaN, lng: 0 }]), null);
});

test("far-north collections never push the view past where the map can draw", () => {
  const [[, west], [north, east]] = openingView([{ lat: 83, lng: -40 }])!;
  assert.ok(north <= 85);
  assert.ok(Number.isFinite(west) && Number.isFinite(east));
});
