// The taxon page's "Sequenced but not yet validated" line (Steve, 2026-10-07):
// how many of a taxon's sequenced records no validation project has given a
// verdict yet, so a taxon waiting for review is not mistaken for a rare one.
//
// No imports, so `node --test` can run its tests without a bundler.

/**
 * The line to show beside the validated count, or null for none: a taxon with
 * no such records, or a server that has not counted them yet, shows nothing.
 */
export function notYetValidatedLine(count: number | null | undefined): string | null {
  if (count == null || !Number.isFinite(count) || count <= 0) return null;
  return `Sequenced but not yet validated: ${Math.round(count).toLocaleString("en-US")}`;
}

/** The ? help beside it. */
export const NOT_YET_VALIDATED_HELP =
  "These records are sequenced, but no validation project has reviewed them yet, " +
  "so the maps do not use them. Those a reviewer confirms join the validated records.";
