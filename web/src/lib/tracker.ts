// How the maps stood up (R/tracker.R; Steve, 2026-10-12): records validated
// after a map was made, scored on it. The words for the Home line, the
// Methods tables and the taxon page's tally live here, so they read the same
// everywhere and can be tested.
//
// No imports, so `node --test` can run its tests without a bundler.

/** One row of GET /api/tracker's table. Shares are null below the server's minimum. */
export interface TrackerRow {
  scheme: "shift" | "skill";
  release: string;
  grade: string;
  subset: string;
  places: number;
  finds: number;
  ranked: number;
  top_half: number | null;
  top_half_ci: number[] | null;
  top_tenth: number | null;
  top_tenth_ci: number[] | null;
  mean_rank: number | null;
  mean_rank_p: number | null;
  top_tenth_p: number | null;
  beats_effort: number | null;
  beats_effort_n: number;
  outside_aoa: number | null;
  beyond_reach: number | null;
  aoa: "known" | "unknown" | "mixed" | null;
  boyce: number | null;
  boyce_effort: number | null;
}

export interface TrackerTally {
  since: string;
  finds?: number | null;
  finds_text: string;
  top_half?: number | null;
  outside?: number | null;
  new_sites?: number | null;
}

export interface TrackerHeadline {
  scheme: "shift" | "skill";
  grade: string;
  subset: string;
  places: number;
  ranked: number;
  top_half: number | null;
  top_half_chance: number;
  beats_effort: number | null;
  effort_chance: number;
}

export interface Tracker {
  grid: string;
  status: "tracking" | "not_started";
  since: string;
  generated_at?: string;
  /** The newest pull the last run read; it stops moving while the nightly is off. */
  pulled_at?: string | null;
  latest_find_on?: string | null;
  current_release?: { id: string; scheme: string; naming: string } | null;
  min_taxon_finds?: number;
  min_ranked_for_share?: number;
  min_ranked_for_boyce?: number;
  finds?: { total: number; by_status: Record<string, number>; retracted: number; held_out?: Record<string, number> };
  coverage?: { finds: number; with_map: number; with_strong_map: number } | null;
  headline?: TrackerHeadline | null;
  releases?: { id: string; scheme: string; naming: string; promoted_at: string; from: string; to: string }[];
  rows: TrackerRow[];
  taxa: (TrackerTally & { taxon: string })[];
}

/** A share as a whole percentage, or a dash when it is withheld. */
export function percent(share: number | null | undefined): string {
  return share == null || !Number.isFinite(share) ? "—" : `${Math.round(share * 100)}%`;
}

/** A date as "3 October 2026". */
export function longDate(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December"];
  return y && m && d ? `${d} ${months[m - 1]} ${y}` : iso;
}

/**
 * The running count on Home, or null while there is nothing to say: the
 * headline row (new sites, strong maps) once it has enough ranked places.
 */
export function homeLine(tracker: Tracker | null | undefined): string | null {
  const h = tracker?.headline;
  if (!tracker || tracker.status !== "tracking" || !h || h.top_half == null) return null;
  const maps = h.scheme === "shift" ? "strong maps" : "maps that passed their test";
  return (
    `${h.ranked.toLocaleString("en-US")} new sites found since ${longDate(tracker.since)}, ` +
    `scored on ${maps} made before they were found: ${percent(h.top_half)} landed in the top half ` +
    `of their map, against ${percent(h.top_half_chance)} by chance.`
  );
}

/** Days without a new pull before the site says scoring is waiting. */
export const PAUSED_AFTER_DAYS = 2;

/**
 * Whether scoring is waiting for the nightly pull: the newest pull the last
 * run read is more than PAUSED_AFTER_DAYS old. No finds are lost meanwhile.
 */
export function scoringPaused(tracker: Tracker | null | undefined, now: Date = new Date()): boolean {
  const at = tracker?.pulled_at ? Date.parse(tracker.pulled_at) : NaN;
  return Number.isFinite(at) && now.getTime() - at > PAUSED_AFTER_DAYS * 86_400_000;
}

export const PAUSED_NOTE =
  "Scoring resumes with the nightly update; records validated meanwhile are scored then, each on the map of its own day.";

/** The taxon page's line, or null when the taxon has no finds yet. */
export function newFindsLine(tally: TrackerTally | null | undefined): string | null {
  if (!tally || !tally.finds_text) return null;
  if (tally.finds == null) return `New finds since this map was made: ${tally.finds_text}`;
  const top = tally.top_half ?? 0;
  return `New finds since this map was made: ${tally.finds.toLocaleString("en-US")}, ${top.toLocaleString("en-US")} in its top half`;
}

/** The ? help beside it. */
export const NEW_FINDS_HELP =
  "Records first validated after this map was made, scored on it. By chance half would fall in its top half. " +
  "Finds tend to come from places people already collect, which flatters any map; " +
  "the Methods page shows the fairer tests.";

/** What the Methods page says before the tables. */
export const TRACKER_CAVEAT =
  "Finds cluster where people already collect, so most fall near a known site and the share in the top half " +
  "runs high for reasons that have little to do with habitat. The honest tests are the new sites (more than " +
  "5 km from every known record of the species), the finds 100–500 km from any known record, and the " +
  "comparison with where everyone else's finds landed. A find 500 km or more from every known record lies " +
  "beyond the maps' 500 km reach by construction, so that row is not a test of the maps: it counts how often " +
  "finds turn up outside the mapped reach, as a species spreads or where its maps were drawn too narrowly.";

const GRADE_WORDS: Record<string, Record<string, string>> = {
  shift: { any: "All maps", strong: "Strong", weak: "Weak", failed: "Failed", untested: "Untested" },
  skill: { any: "All maps", passed: "Passed (old test)", failed: "Did not pass", untested: "Untested" },
};

/** A grade's label in the tables, under its scheme. */
export function gradeLabel(scheme: string, grade: string): string {
  return GRADE_WORDS[scheme]?.[grade] ?? grade;
}

const SUBSET_WORDS: Record<string, string> = {
  all: "All finds",
  new_site: "New sites",
  known_site: "Near a known site",
  band_under_100: "Under 100 km from a known site",
  band_100_500: "100–500 km from a known site",
  band_500_plus: "500 km or more: beyond the maps' reach",
  band_none: "First record of the species",
  channel_triage: "Validated from the triage card (left out above)",
  channel_priority_sort: "Validated from the priority list (left out above)",
  channel_auto: "Validated automatically (left out above)",
  channel_other: "Validated another way (left out above)",
};

export function subsetLabel(subset: string): string {
  return SUBSET_WORDS[subset] ?? subset;
}

/** The scheme's name over its table. */
export function schemeLabel(scheme: string): string {
  return scheme === "shift"
    ? "Since the rebuild: graded against clustered nulls, named by DNA"
    : "Before the rebuild: the old pass/fail test, named by record";
}

/** The rows of one scheme's table: every release together, in a fixed order. */
export function schemeRows(tracker: Tracker, scheme: string, subsets: readonly string[]): TrackerRow[] {
  const grades = Object.keys(GRADE_WORDS[scheme] ?? {});
  return tracker.rows
    .filter((r) => r.scheme === scheme && r.release === "all" && subsets.includes(r.subset))
    .sort((a, b) => grades.indexOf(a.grade) - grades.indexOf(b.grade) || subsets.indexOf(a.subset) - subsets.indexOf(b.subset));
}

export const SUBSETS_MAIN = [
  "all", "new_site", "known_site", "channel_triage", "channel_priority_sort", "channel_auto", "channel_other",
] as const;
export const SUBSETS_DISTANCE = ["band_under_100", "band_100_500", "band_500_plus", "band_none"] as const;
