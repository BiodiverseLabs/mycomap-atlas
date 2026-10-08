// The street map under every habitat map on the site.
//
// Stadia Maps serves it (Steve, 2026-10-07): OpenStreetMap's own tile servers
// are for light use only, and launch traffic would exceed their policy. Stadia
// authenticates a browser by the site it is on (the domains listed in its
// dashboard; localhost works for development), so no key appears here, in the
// built app or on the server. The style is OSM Bright, the closest to the
// OpenStreetMap look the maps had before.
//
// No imports, so `node --test` can run its tests without a bundler.

/** {r} asks Leaflet for the double-resolution tile on high-density screens. */
export const BASEMAP_URL = "https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png";

/** Stadia's terms require all three credits wherever its tiles are shown. */
export const BASEMAP_ATTRIBUTION =
  '&copy; <a href="https://stadiamaps.com/" target="_blank" rel="noreferrer">Stadia Maps</a> ' +
  '&copy; <a href="https://openmaptiles.org/" target="_blank" rel="noreferrer">OpenMapTiles</a> ' +
  '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a> contributors';
