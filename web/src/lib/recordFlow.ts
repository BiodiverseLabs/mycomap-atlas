// Where mycomap.org's records go before Atlas fits a map (Methods, Records).
//
// The counts come from the pull's manifest through the API; the words are
// here. Each step names how many records it left out, optionally split by
// reason, and the bars are what is left after each step. A flow whose steps do
// not add up to the records used is not shown at all: a wrong bar is worse
// than none.

export type FlowPart = { id: string; count: number };
export type FlowStep = { id: string; removed: number; parts?: FlowPart[] };
export type RecordFlowData = {
  pulled_at: string;
  /** Every record on mycomap.org when the pull was made. */
  total: number;
  /** The records the maps are fitted on. */
  used: number;
  /** iNaturalist's accuracy cutoff for this pull, in metres. */
  max_accuracy_m: number;
  steps: FlowStep[];
};

export type FlowRow = {
  id: string;
  label: string;
  left: number;
  removed: number;
  why: string;
  parts: { label: string; count: number }[];
};

/** "1 km", "2 km", "500 m". */
export function distanceLabel(metres: number): string {
  return metres >= 1000 ? `${+(metres / 1000).toFixed(1)} km` : `${Math.round(metres)} m`;
}

type StepText = {
  label: string;
  why: (d: RecordFlowData) => string;
  parts?: Record<string, string>;
  /** A part not listed above, named from its slug. */
  otherPart?: (slug: string) => string;
};

export const STEP_TEXT: Record<string, StepText> = {
  dna: {
    label: "Name confirmed by DNA",
    why: () =>
      "Photo identifications, herbarium names and records still waiting for a sequence. A map trained on a wrong name is confidently wrong.",
  },
  coordinates: {
    label: "With coordinates",
    why: () => "No place was recorded, so there is nothing to map.",
  },
  north_america: {
    label: "In North America",
    why: () =>
      "Collected outside the United States, Canada, Mexico, Puerto Rico and the US Virgin Islands, which the maps cover.",
  },
  obscured: {
    label: "Exact spot not hidden",
    why: () => "The observer or iNaturalist hides the exact spot, often for a rare species. Atlas keeps it hidden.",
  },
  inat_coarse: {
    label: "iNaturalist spot precise enough",
    why: (d) =>
      `iNaturalist places it only to within more than ${distanceLabel(d.max_accuracy_m)}, too loose for Atlas to trust which map cell it falls in.`,
  },
  other_coarse: {
    label: "A usable point from every other source",
    why: () => "Records from other sources with no point Atlas can use.",
    parts: {
      mo_place_centre: "Mushroom Observer, only a large named place's centre",
      mo_deleted: "Mushroom Observer, deleted at the source",
      mo_uncached: "Mushroom Observer, no answer from the source yet",
      mo_unexplained: "Mushroom Observer, no point Atlas could check",
      mycoportal: "MyCoPortal, no precise point",
      sequences: "Sequences without a usable point",
      genbank: "GenBank, no usable point",
    },
    // A source no rule above explains: records that changed while the pull ran.
    otherPart: (slug) => `${sourceName(slug)}, changed while the pull ran`,
  },
  name: {
    label: "Species name settled by DNA",
    why: () => "The record's sequences do not name one species.",
    parts: {
      disagree: "sequences name different species",
      no_named_sequence: "no approved named sequence yet",
      genus_only: "sequence names only a genus",
      sequence_one_word: "sequence name is one word",
      rank_above_species: "named only above species level",
      not_a_species_name: "not a species name",
    },
  },
  excluded: {
    label: "Not on the exclusion list",
    why: () => "Found by hand to be errors in their source, such as plants named by their own sequences.",
  },
  other_kingdom: {
    label: "A fungus, by its name",
    why: () => "Named by its sequence as a plant, animal or other organism that is not a fungus.",
  },
};

const SOURCE_NAMES: Record<string, string> = {
  inaturalist: "iNaturalist",
  mushroom_observer: "Mushroom Observer",
  mo_observations: "Mushroom Observer",
  mycoportal: "MyCoPortal",
  sequences: "Sequences",
  genbank: "GenBank",
};

/** A source's name from its slug ("inaturalist" → "iNaturalist"). */
export function sourceName(slug: string): string {
  return SOURCE_NAMES[slug] ?? slug.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}

/** What a step's part is called, or null when this page cannot name it. */
function partLabel(stepId: string, partId: string): string | null {
  const text = STEP_TEXT[stepId];
  return text?.parts?.[partId] ?? (text?.otherPart && /^[a-z][a-z0-9_]*$/.test(partId) ? text.otherPart(partId) : null);
}

/** Whether every bar adds up: each step's parts make its count, no count is
 *  negative, every step is one this page can describe, and what is left after
 *  the last step is exactly the records used. */
export function flowAddsUp(d: RecordFlowData): boolean {
  let left = d.total;
  for (const s of d.steps) {
    if (!STEP_TEXT[s.id] || !Number.isInteger(s.removed) || s.removed < 0) return false;
    if (s.parts && s.parts.reduce((n, p) => n + p.count, 0) !== s.removed) return false;
    if (s.parts?.some((p) => !partLabel(s.id, p.id) || !Number.isInteger(p.count) || p.count < 0)) return false;
    left -= s.removed;
    if (left < 0) return false;
  }
  return left === d.used;
}

/** The rows to draw, or null when the flow does not add up. */
export function flowRows(d: RecordFlowData): FlowRow[] | null {
  if (!flowAddsUp(d)) return null;
  let left = d.total;
  return d.steps.map((s) => {
    left -= s.removed;
    const text = STEP_TEXT[s.id];
    return {
      id: s.id,
      label: text.label,
      left,
      removed: s.removed,
      why: text.why(d),
      parts: (s.parts ?? []).filter((p) => p.count > 0).map((p) => ({ label: partLabel(s.id, p.id)!, count: p.count })),
    };
  });
}
