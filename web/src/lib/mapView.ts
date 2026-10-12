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

/**
 * Which ground a map shows. "accessible", the default: within REACH_KM of the
 * records, where the model was fitted. "full": a strong map's full-extent
 * view, the same colour scale carried everywhere conditions resemble its
 * known sites and hatched elsewhere. That is potential, not range: the model
 * cannot tell ground nobody surveyed from ground searched without a find.
 */
export type MapView = "accessible" | "full";

/** The part of a model a map overlay needs. */
export interface ViewableModel {
  bounds?: Extent | null;
  full_map?: { bounds?: Extent | null } | null;
}

/** Whether a model can show the full view: only a strong map has one. */
export function hasFullView(model?: ViewableModel | null): boolean {
  return model?.full_map?.bounds != null;
}

/**
 * What a model's overlay draws in the view asked for: the full-extent PNG
 * where the model has one, else its default map (a weak or failed map makes
 * no claim beyond its reach, so it stays as it is). null with no map at all.
 */
export function mapOverlay(
  model: ViewableModel | null | undefined,
  view: MapView,
): { view: MapView; bounds: Bounds } | null {
  const full = view === "full" && hasFullView(model) ? model!.full_map!.bounds! : null;
  const extent = full ?? model?.bounds ?? null;
  if (!extent) return null;
  return {
    view: full ? "full" : "accessible",
    bounds: [[extent.south, extent.west], [extent.north, extent.east]],
  };
}
