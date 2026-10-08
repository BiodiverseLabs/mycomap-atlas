// How much a map's null test vouches for it (R/map.R, atlas_map_grade;
// Steve, 2026-10-08). Only a strong map makes a claim anywhere; weak and
// failed maps are drawn faint on their taxon page and nowhere else.
//
//   strong    passed against shifted nulls, which keep the taxon's clustering
//   weak      not shown to beat clustered collecting: better than chance on
//             held-out ground without passing, or a pass against scattered
//             nulls from before the switch (they passed 74% of virtual
//             species that knew nothing)
//   failed    no better than chance on held-out ground
//   untested  no null test was run

export type Grade = "strong" | "weak" | "failed" | "untested";

/** Production's null design since 2026-10-08. */
export const NULL_DESIGN = "shift";

interface Gradable {
  skill?: string;
  grade?: string;
  auc_mean?: number;
  boyce?: number;
  boyce_mean?: number;
  null?: { design?: string; observed_auc?: number; observed_boyce?: number } | null;
}

const GRADES: readonly string[] = ["strong", "weak", "failed", "untested"];

/** A model's grade: as recorded, or worked out for a fit from before grades. */
export function mapGrade(model: Gradable | null | undefined): Grade {
  if (!model) return "untested";
  if (model.grade && GRADES.includes(model.grade)) return model.grade as Grade;
  if (model.skill === "passed") return model.null?.design === NULL_DESIGN ? "strong" : "weak";
  if (model.skill !== "failed") return "untested";
  const auc = model.auc_mean ?? model.null?.observed_auc;
  const boyce = model.boyce ?? model.boyce_mean ?? model.null?.observed_boyce;
  return auc != null && auc > 0.5 && boyce != null && boyce > 0 ? "weak" : "failed";
}

/** Drawn faint: tested, and not strong. */
export function isFaint(grade: Grade): boolean {
  return grade === "weak" || grade === "failed";
}

/** The line laid over a faint map, or null for one that is not. */
export function gradeNote(grade: Grade): string | null {
  if (grade === "weak") {
    return "Not shown to beat clustered collecting: read this map as a hint, not a finding.";
  }
  if (grade === "failed") return "Failed its null test: this map says little about habitat.";
  return null;
}

/** The short verdict in the comparison table. */
export function gradeVerdict(grade: Grade): string {
  return { strong: "Yes", weak: "Not shown", failed: "No", untested: "Not tested" }[grade];
}
