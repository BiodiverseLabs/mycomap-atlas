/**
 * The note on a small-model map that failed its null test.
 *
 * With 3 to 19 sites a taxon's null test has too little to go on: the null
 * models' AUC spreads so widely (sd 0.25 at 3-4 sites, 0.10 at 16-19) that a
 * sound map rarely beats all nineteen. So a failed test there does not mean a
 * bad map, and it does not mean a good one either.
 *
 * This note used to add how often such maps had clear skill in the sparse
 * study (well-recorded taxa thinned to a few sites at random). That rate was
 * borrowed from fungi that are common and widespread; a taxon with a handful
 * of sites is usually rare, or a lineage known from one region, and its maps
 * need not behave the same way. The note no longer offers it as reassurance.
 */
export function sparseFailedNote(sites: number): string {
  const count = sites > 0 ? `${sites} sites` : "so few sites";
  return (
    `Too few sites to tell: with ${count}, no test can say whether this map knows anything. ` +
    `Read it as a hint about where to look, not a finding.`
  );
}
