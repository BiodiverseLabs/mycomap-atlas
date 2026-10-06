// Where a taxon's maps open.
//
// A model's raster covers the whole ground it was fitted on, often a
// continent or more, so fitting the map to it opens on the world with the
// collections a few pixels wide. The colour stops REACH_KM from the nearest
// record, so the collections widened by that much hold everything a map
// claims: that is where a map opens.
//
// No imports, so `node --test` can run its tests without a bundler.

/** How far colour reaches from the nearest record, as the API draws it. */
export const REACH_KM = 500;

const KM_PER_DEGREE = 111.32;
// Leaflet's Web Mercator stops here.
const MAX_LAT = 85;

export type Bounds = [[number, number], [number, number]];

export interface Point {
  lat: number;
  lng: number;
}

export interface Extent {
  south: number;
  west: number;
  north: number;
  east: number;
}

/**
 * The view a taxon's maps open on: its collections, widened by REACH_KM and
 * kept inside the raster when there is one. With no collections, the raster;
 * with neither, null, and the map stays where it was made.
 */
export function openingView(points: readonly Point[], raster?: Extent | null): Bounds | null {
  const usable = points.filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lng));
  if (usable.length === 0) {
    return raster ? [[raster.south, raster.west], [raster.north, raster.east]] : null;
  }
  const lats = usable.map((p) => p.lat);
  const lngs = usable.map((p) => p.lng);
  let south = Math.min(...lats);
  let north = Math.max(...lats);
  const latPad = REACH_KM / KM_PER_DEGREE;
  // A degree of longitude shrinks towards the poles, so widen by it at the
  // edge nearest a pole, where the same distance spans the most degrees.
  const poleward = Math.min(Math.max(Math.abs(south), Math.abs(north)) + latPad, 80);
  const lngPad = REACH_KM / (KM_PER_DEGREE * Math.cos((poleward * Math.PI) / 180));
  let west = Math.min(...lngs) - lngPad;
  let east = Math.max(...lngs) + lngPad;
  south = Math.max(south - latPad, -MAX_LAT);
  north = Math.min(north + latPad, MAX_LAT);
  if (raster) {
    // Only where the two overlap; a raster that misses the points entirely
    // says nothing about where to look, so the points win.
    const s = Math.max(south, raster.south);
    const n = Math.min(north, raster.north);
    const w = Math.max(west, raster.west);
    const e = Math.min(east, raster.east);
    if (s < n && w < e) [south, north, west, east] = [s, n, w, e];
  }
  return [[south, west], [north, east]];
}
