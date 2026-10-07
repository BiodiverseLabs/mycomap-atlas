// Which maps a taxon's page shows, from the models it has.
//
// 50 or more sites: the three full models. 20 to 49: Maxent, the small-model
// ensemble in the boosted trees' place (below 50 sites they rank ground worse
// than Maxent, R/algorithms.R), and the random forest. 3 to 19: the ensemble
// alone.
//
// No imports, so `node --test` can run its tests without a bundler.

export type Panel = "maxnet" | "xgboost" | "rf" | "esm";

/** The three fitted side by side for taxa with 50 or more sites. */
export const FULL_MODELS: Panel[] = ["maxnet", "xgboost", "rf"];
/** Taxa with 20 to 49 sites: the ensemble where the boosted trees were. */
export const MIDDLE_MODELS: Panel[] = ["maxnet", "esm", "rf"];
/** The one fitted for taxa with 3 to 19 sites. */
export const SPARSE_MODELS: Panel[] = ["esm"];

/** Below this many sites a small-model ensemble's null test cannot tell. */
export const SPARSE_BELOW = 20;

/** The maps a taxon's page shows, given which of its models exist. */
export function shownModels(models: Partial<Record<Panel, unknown>>): Panel[] {
  const full = FULL_MODELS.some((a) => models[a]);
  if (models.esm && !full) return SPARSE_MODELS;
  if (models.esm && !models.xgboost) return MIDDLE_MODELS;
  return FULL_MODELS;
}
