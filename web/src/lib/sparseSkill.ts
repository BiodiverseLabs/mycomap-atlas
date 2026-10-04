/**
 * How often a small-model ensemble of a given size had clear skill, for maps
 * whose own null test cannot say.
 *
 * With 3 to 19 sites a taxon's null test has too little to go on: the null
 * models' AUC spreads so widely (sd 0.25 at 3-4 sites, 0.10 at 16-19) that a
 * sound map rarely beats all nineteen. So a failed test there does not mean
 * a bad map. What can be said is how such maps did when they could be
 * checked: in the sparse study (2026-09-30, 118 well-recorded taxa thinned to
 * a few sites and scored on all their held-out detections), the share with
 * clear skill — AUC above 0.6 and a positive Boyce index — was 40% at 3
 * sites, 58% at 4, 50% at 5, 60% at 8, 65% at 12 and 69% at 16.
 */
export function sparseSkillShare(sites: number): string {
  if (sites < 8) return "about half";
  if (sites < 12) return "about 6 in 10";
  return "about 2 in 3";
}

/** The note on a small-model map that failed its null test. */
export function sparseFailedNote(sites: number): string {
  return (
    `Too few sites to test this map against chance on its own. When well-recorded fungi were ` +
    `cut down to ${sites} sites, ${sparseSkillShare(sites)} of such maps were clearly better than chance.`
  );
}
