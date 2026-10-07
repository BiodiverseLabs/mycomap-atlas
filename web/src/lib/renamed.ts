// Old taxon links. A provisional name is renamed on mycomap.org when its
// lineage gets a formal name; a page, citation or link made under the old name
// is sent to the name its records have now (/api/names, R/names.R).

export interface Resolution {
  name: string;
  how: "current" | "spelling" | "renamed";
}

/** Where a taxon page should go instead, if anywhere: the current name's page. */
export function renamedTaxonPath(requested: string, resolution: Resolution | null | undefined): string | null {
  if (!resolution || resolution.how === "current" || resolution.name === requested) return null;
  const query = new URLSearchParams({ from: requested, how: resolution.how });
  return `/taxa/${encodeURIComponent(resolution.name)}?${query.toString()}`;
}

/** The line a page shows when it was reached under another name. */
export function reachedFromNote(name: string, search: string): string | null {
  const params = new URLSearchParams(search);
  const from = params.get("from");
  if (!from || from === name) return null;
  return params.get("how") === "spelling"
    ? `${from} is another spelling of this name.`
    : `Formerly ${from}: these records were renamed on mycomap.org.`;
}
