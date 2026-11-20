import type { RecordFlowData } from "./recordFlow.ts";

// Test data in the shape /api/status serves. Some counts are the 19 November
// 2026 pull's (Mushroom Observer place centres 2,533, names 3,293 / 2,313 /
// 1,142, excluded 55, used 145,258); the rest are made up to add up.
export const FLOW_FIXTURE: RecordFlowData = {
  pulled_at: "2026-11-19T07:13:52Z",
  total: 199_000,
  used: 145_258,
  max_accuracy_m: 1000,
  steps: [
    { id: "dna", removed: 27_933 },
    { id: "coordinates", removed: 6_000 },
    { id: "north_america", removed: 2_500 },
    { id: "obscured", removed: 3_000 },
    { id: "inat_coarse", removed: 4_000 },
    {
      id: "other_coarse",
      removed: 3_460,
      parts: [
        { id: "mo_place_centre", count: 2_533 },
        { id: "mo_deleted", count: 27 },
        { id: "mycoportal", count: 400 },
        { id: "sequences", count: 300 },
        { id: "genbank", count: 200 },
      ],
    },
    {
      id: "name",
      removed: 6_794,
      parts: [
        { id: "disagree", count: 3_293 },
        { id: "no_named_sequence", count: 2_313 },
        { id: "genus_only", count: 1_142 },
        { id: "not_a_species_name", count: 46 },
      ],
    },
    { id: "excluded", removed: 55 },
  ],
};

