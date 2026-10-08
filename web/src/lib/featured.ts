// The featured species on the home page (Steve, 2026-10-08): a short list
// chosen by hand after the rebuild from strong maps, such as a familiar
// species, an ectomycorrhizal one and a provisional one. The list lives in
// web/public/featured.json, so choosing them is an edit, not a code change.
// While it is empty, the slot is not shown at all.
//
// No imports, so `node --test` can run its tests without a bundler.

/** Where the site reads the list from. */
export const FEATURED_PATH = "/featured.json";

/** At most this many are shown, however many are listed. */
export const FEATURED_MAX = 3;

export interface FeaturedTaxon {
  name: string;
  /** One line on why it is worth a look; optional. */
  note?: string;
}

/**
 * The list from featured.json: names trimmed, blanks and repeats dropped,
 * anything malformed ignored, at most FEATURED_MAX. A missing or broken file
 * reads as an empty list, so the home page never breaks over it.
 */
export function readFeatured(json: unknown): FeaturedTaxon[] {
  const items = json && typeof json === "object" ? (json as { taxa?: unknown }).taxa : undefined;
  if (!Array.isArray(items)) return [];
  const out: FeaturedTaxon[] = [];
  const seen = new Set<string>();
  for (const item of items) {
    const raw = typeof item === "string" ? { name: item } : item;
    if (!raw || typeof raw !== "object") continue;
    const name = typeof (raw as { name?: unknown }).name === "string" ? (raw as { name: string }).name.trim() : "";
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    const note = (raw as { note?: unknown }).note;
    out.push(typeof note === "string" && note.trim() ? { name, note: note.trim() } : { name });
    if (out.length === FEATURED_MAX) break;
  }
  return out;
}

/** Whether the home page shows the featured slot at all. */
export function showFeatured(list: readonly FeaturedTaxon[]): boolean {
  return list.length > 0;
}
