import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Download } from "lucide-react";
import { Link } from "wouter";

import { ApiDown, Loading, Stat, Th } from "@/components/Common";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { checklistUrl, getLayers, getPrior, getRegions, getStatus, getTaxaCount, type Region } from "@/lib/api";
import { usePageMeta } from "@/lib/usePageMeta";
import { formatNumber, formatWhen } from "@/lib/utils";

// About 20 independent localities is where a map becomes worth drawing.
const THRESHOLDS = [5, 10, 20, 30, 50, 100];
const PUBLISH_AT = 20;

const COUNTRIES = [
  ["US", "United States"],
  ["CA", "Canada"],
  ["MX", "Mexico"],
] as const;

/** How a checklist download names its region: by code, or by name when it has none. */
const regionKey = (region: Region) => region.code || region.region;

/**
 * Every taxon recorded in a state, province or territory, as a CSV that opens
 * in Excel. One region, one country, or everything.
 */
function Checklists() {
  const regions = useQuery({ queryKey: ["regions"], queryFn: getRegions });
  const [picked, setPicked] = useState("");
  const list = regions.data?.regions ?? [];
  const countries = [...new Set(list.map((r) => r.country))];
  const selected = list.find((r) => regionKey(r) === picked) ?? null;
  const button =
    "inline-flex items-center gap-1.5 rounded-md bg-myco-green px-3 py-2 text-sm font-medium text-white hover:bg-myco-green/90";

  return (
    <section id="checklists">
      <SectionTitle>Species checklists by state and province</SectionTitle>
      <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
        Every taxon with a DNA-validated record in a US state or territory, Canadian province or
        territory, or Mexican state, and every taxon its maps call likely (they agree) or possible
        (only one of them sees habitat) there though nobody has sequenced it there yet, marked as
        such: survey targets. Each row has the records,
        independent localities, what the maps say and a link to the map. The CSV opens in Excel
        and Google Sheets. A species missing from a list may still grow there: only species with
        records or a map that beat its null models can be listed.
      </p>
      <Card className="max-w-3xl">
        <CardContent className="space-y-4 p-4 text-sm">
          {regions.isError && <p className="text-muted-foreground">Checklists are not available on this server yet.</p>}
          {regions.isLoading && <Loading />}
          {list.length > 0 && (
            <>
              <div className="flex flex-wrap items-end gap-3">
                <label className="flex flex-col gap-1 text-xs text-muted-foreground">
                  State, province or territory
                  <select
                    value={picked}
                    onChange={(event) => setPicked(event.target.value)}
                    className="min-w-[16rem] rounded-md border border-[#A87146]/30 bg-white px-2 py-2 text-sm text-[#4a3728]"
                  >
                    <option value="">Choose one…</option>
                    {countries.map((country) => (
                      <optgroup key={country} label={country}>
                        {list
                          .filter((r) => r.country === country)
                          .map((r) => (
                            <option key={regionKey(r)} value={regionKey(r)}>
                              {r.region} ({formatNumber(r.taxa)} recorded
                              {r.likely ? `, ${formatNumber(r.likely)} more likely` : ""}
                              {r.possible ? `, ${formatNumber(r.possible)} possible` : ""})
                            </option>
                          ))}
                      </optgroup>
                    ))}
                  </select>
                </label>
                {selected && (
                  <a href={checklistUrl({ region: regionKey(selected) })} className={button}>
                    <Download className="h-4 w-4" /> {selected.region} CSV
                  </a>
                )}
              </div>
              <p className="text-xs text-muted-foreground">
                Or a whole country:{" "}
                {COUNTRIES.map(([code, label], i) => (
                  <span key={code}>
                    {i > 0 && " · "}
                    <a href={checklistUrl({ region: code })} className="text-myco-green hover:underline">
                      {label}
                    </a>
                  </span>
                ))}{" "}
                · or{" "}
                <a href={checklistUrl()} className="text-myco-green hover:underline">
                  everything
                </a>{" "}
                (one row per taxon per region, about 6 MB). For a copy that stays current, give the
                download link to Excel's Data › From Web or Google Sheets' IMPORTDATA.
              </p>
            </>
          )}
        </CardContent>
      </Card>
    </section>
  );
}

function megabytes(bytes: number): string {
  return bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} kB`;
}

/** The location prior, for reading the maps from another program. */
function Prior() {
  const prior = useQuery({ queryKey: ["prior"], queryFn: getPrior, retry: false });
  return (
    <section id="prior">
      <SectionTitle>Location prior</SectionTitle>
      <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
        For a program that weighs what a photo shows by where it was taken, as MycoMap Vision
        does: every map that beat its null models, as ranks by 20 km cell over the whole of the
        taxon's reach, the poor ground as well as the good. Ground the maps cannot judge is left
        unranked, and a taxon with no such map is simply not listed, which means no information,
        not unlikely. A rank is the map's own percentile, not a probability: calibrate it on
        records of your own before weighting by it. The grid file says how to find a point's
        cell, with a few lines of Python.
      </p>
      <Card className="max-w-3xl">
        <CardContent className="space-y-2 p-4 text-sm">
          {prior.isLoading && <Loading />}
          {prior.isError && <p className="text-muted-foreground">Not built yet: it comes with the next finished release.</p>}
          {prior.data && (
            <>
              <p className="text-[#5c4a3a]">
                {formatNumber(prior.data.taxa)} taxa, {formatNumber(prior.data.rows)} taxon and cell pairs
                {prior.data.release ? `, release ${prior.data.release}` : ""}.
              </p>
              <ul className="space-y-1">
                {prior.data.files.map((file) => (
                  <li key={file.name}>
                    <a href={file.url} className="text-myco-green hover:underline">
                      {file.name}
                    </a>{" "}
                    <span className="text-xs text-muted-foreground tabular-nums">{megabytes(file.bytes)}</span>
                  </li>
                ))}
              </ul>
              <p className="text-xs text-muted-foreground">
                Columns, the grid and checksums: <a href="/api/prior" className="text-myco-green hover:underline">/api/prior</a>.
              </p>
            </>
          )}
        </CardContent>
      </Card>
    </section>
  );
}

export default function Data() {
  usePageMeta({
    title: "Data",
    description:
      "What Atlas's maps are built from: DNA-validated MycoMap collections and environmental layers, and species checklists by state and province.",
  });
  const status = useQuery({ queryKey: ["status"], queryFn: getStatus });
  const layers = useQuery({ queryKey: ["layers"], queryFn: () => getLayers("draft") });
  const readiness = useQuery({
    queryKey: ["readiness"],
    enabled: status.data?.ready === true,
    queryFn: async () =>
      Promise.all(
        THRESHOLDS.map(async (threshold) => ({ threshold, taxa: await getTaxaCount(threshold) })),
      ),
  });

  return (
    <>
      <PageHeader title="Data">
        What the maps are built from: MycoMap collections confirmed by DNA, and environmental
        layers that cover all of North America on an equal-area grid, so a cell means the same
        ground in Oaxaca and in Nunavut.
      </PageHeader>
      <Page>
        {status.isError && <ApiDown />}

        <section>
          <SectionTitle>Training records</SectionTitle>
          <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
            A record counts when it is green in at least one MycoMap validation project (a red in
            another does not rule it out), has coordinates accurate to 1 km or better, and carries
            a species-level name — provisional names included, since a third of the mappable taxa
            have no formal name yet. Unassessed records, photo identifications and eDNA are left
            out.
          </p>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label="Records" value={formatNumber(status.data?.records)} />
            <Stat label="Taxa" value={formatNumber(status.data?.taxa)} />
            <Stat label="Last pull" value={formatWhen(status.data?.pulledAt).split(",")[0]} />
            <Stat label="Fingerprint" value={status.data?.fingerprint?.slice(0, 12) ?? "—"} />
          </div>

          <Card className="mt-4 max-w-xl">
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
              <CardTitle className="text-base text-[#4a3728]">How many taxa could be mapped</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <table className="w-full text-sm">
                <thead className="text-xs uppercase tracking-wider text-muted-foreground">
                  <tr className="border-b">
                    <Th>Independent localities</Th>
                    <Th right>Taxa</Th>
                  </tr>
                </thead>
                <tbody>
                  {readiness.isLoading && (
                    <tr>
                      <td className="px-4 py-3 text-muted-foreground" colSpan={2}>
                        Counting…
                      </td>
                    </tr>
                  )}
                  {readiness.data?.map((row) => (
                    <tr
                      key={row.threshold}
                      className={`border-b last:border-0 ${row.threshold === PUBLISH_AT ? "bg-myco-green/10" : ""}`}
                    >
                      <td className="px-4 py-2">
                        {row.threshold} or more
                        {row.threshold === PUBLISH_AT && (
                          <span className="ml-2 text-xs text-myco-green">enough for a map</span>
                        )}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatNumber(row.taxa)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardContent>
          </Card>
        </section>

        <Checklists />

        <Prior />

        <section>
          <SectionTitle>Environmental layers</SectionTitle>
          <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
            Every source is global, because the familiar United States products stop at the
            border while British Columbia alone holds 8% of the records. The cost: no continental
            map of tree species exists, so tree cover is carried as a fraction, and a model
            cannot be read as knowing which host a fungus needs.
          </p>
          {layers.isLoading && <Loading />}
          <div className="grid gap-4 md:grid-cols-2">
            {(layers.data?.layers ?? []).map((layer) => (
              <Card key={layer.id}>
                <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <CardTitle className="text-base text-[#4a3728]">{layer.title}</CardTitle>
                    <Badge variant={layer.built ? "default" : "secondary"}>
                      {layer.built ? "built" : "not built"}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent className="p-4 space-y-2 text-sm">
                  <p className="text-[#5c4a3a]">
                    {layer.url ? (
                      <a href={layer.url} target="_blank" rel="noreferrer" className="text-myco-green hover:underline">
                        {layer.source}
                      </a>
                    ) : (
                      layer.source
                    )}{" "}
                    · <span className="text-muted-foreground">{layer.license}</span>
                  </p>
                  {layer.built && (
                    <p className="text-xs text-muted-foreground tabular-nums">
                      {formatNumber(layer.bands?.length)} band{layer.bands?.length === 1 ? "" : "s"} ·{" "}
                      {formatNumber(layer.cellSizeM)} m cells · {layer.sizeMb} MB · built{" "}
                      {formatWhen(layer.builtAt).split(",")[0]}
                    </p>
                  )}
                  {layer.bands && layer.bands.length > 0 && (
                    <div className="flex flex-wrap gap-1">
                      {layer.bands.map((band) => (
                        <span
                          key={band}
                          className="rounded border border-[#A87146]/20 px-1.5 py-0.5 text-xs text-muted-foreground"
                        >
                          {band}
                        </span>
                      ))}
                    </div>
                  )}
                  <p className="text-xs text-muted-foreground">{layer.citation}</p>
                </CardContent>
              </Card>
            ))}
          </div>
          <p className="mt-4 text-sm text-[#5c4a3a]">
            Every dataset, package and intermediate file, with links and what is published:{" "}
            <Link href="/sources" className="text-myco-green hover:underline">
              Data and sources
            </Link>
            .
          </p>
        </section>
      </Page>
    </>
  );
}
