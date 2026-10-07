import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Check, Copy, Download, ExternalLink } from "lucide-react";

import { Th } from "@/components/Common";
import { SectionTitle } from "@/components/Layout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ALGORITHM_LABELS,
  absoluteUrl,
  checklistUrl,
  embedPath,
  getTaxonRegions,
  imageUrl,
  type Algorithm,
  type RegionVerdict,
  type TaxonRegion,
} from "@/lib/api";
import { formatNumber } from "@/lib/utils";

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      onClick={() => {
        void navigator.clipboard?.writeText(text).then(() => {
          setCopied(true);
          window.setTimeout(() => setCopied(false), 1500);
        });
      }}
      className="inline-flex items-center gap-1 rounded-md bg-myco-green px-3 py-1.5 text-xs font-medium text-white hover:bg-myco-green/90"
    >
      {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
      {copied ? "Copied" : label}
    </button>
  );
}

const codeClass =
  "w-full rounded-md border border-[#A87146]/20 bg-[#f8f5f0] p-2 font-mono text-xs text-[#4a3728]";

/** A read-only box of text to copy, selected whole on a click. */
function CodeBox({ value }: { value: string }) {
  return (
    <textarea
      readOnly
      value={value}
      rows={3}
      onFocus={(event) => event.currentTarget.select()}
      className={`${codeClass} resize-none`}
    />
  );
}

/** The same for a single line, such as a link. */
function CodeLine({ value }: { value: string }) {
  return (
    <input readOnly value={value} onFocus={(event) => event.currentTarget.select()} className={codeClass} />
  );
}

const VERDICT_STYLE: Record<RegionVerdict, string> = {
  likely: "bg-myco-green/15 text-myco-green font-medium",
  possible: "bg-amber-100 text-amber-800",
  unlikely: "bg-[#A87146]/10 text-[#7a5a3f]",
  "beyond reach": "text-muted-foreground italic",
  "no map": "text-muted-foreground",
};

const VERDICT_LABEL: Record<RegionVerdict, string> = {
  likely: "Likely",
  possible: "Possible",
  unlikely: "Unlikely",
  "beyond reach": "Beyond reach",
  "no map": "—",
};

const percent = (share: number | null) => (share == null ? "—" : `${Math.round(share * 100)}%`);

/** Recorded states first, most records first; then likely, then possible, most suitable first. */
function byEvidence(a: TaxonRegion, b: TaxonRegion) {
  const tier = (r: TaxonRegion) => (r.model === "likely" ? 0 : r.model === "possible" ? 1 : 2);
  return (
    b.records - a.records ||
    tier(a) - tier(b) ||
    (b.suitable_share ?? 0) - (a.suitable_share ?? 0) ||
    (b.best_share ?? 0) - (a.best_share ?? 0) ||
    a.region.localeCompare(b.region)
  );
}

/**
 * Where a taxon occurs, by state and province: where it has DNA-validated
 * records, and where its maps say it is likely though nobody has sequenced it
 * there yet.
 */
function WhereItOccurs({ name }: { name: string }) {
  const regions = useQuery({ queryKey: ["taxon-regions", name], queryFn: () => getTaxonRegions(name) });
  const rows = [...(regions.data?.regions ?? [])].sort(byEvidence);
  const recorded = rows.filter((r) => r.records > 0).length;
  const likelyOnly = rows.filter((r) => r.records === 0 && r.model === "likely").length;
  const possibleOnly = rows.filter((r) => r.records === 0 && r.model === "possible").length;
  const minShare = percent(regions.data?.min_share ?? 0.1);
  const csv = absoluteUrl(checklistUrl({ taxon: name }));

  return (
    <section id="where">
      <SectionTitle>Where it occurs</SectionTitle>
      <p className="mb-3 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
        States and provinces where it has DNA-validated records, and those where its maps say it may
        grow though nobody has sequenced it there yet. A state is <em>likely</em> when, averaged over
        its maps that beat their null models, at least {minShare} of it is as suitable as the poorer
        tenth of the places it has been found: the maps agree. It is <em>possible</em> when only one
        map rates that much of it suitable: the maps disagree, and one sees habitat the others do
        not. <em>Beyond reach</em> means most of the state lies over 500 km from any record, where
        the maps make no claim.
      </p>
      <Card className="max-w-4xl">
        <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-2">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <CardTitle className="text-base text-[#4a3728]">
              {regions.data
                ? `Recorded in ${formatNumber(recorded)}${
                    likelyOnly ? ` · likely in ${formatNumber(likelyOnly)} more` : ""
                  }${possibleOnly ? ` · possible in ${formatNumber(possibleOnly)}` : ""}`
                : "States and provinces"}
            </CardTitle>
            {rows.length > 0 && (
              <a
                href={checklistUrl({ taxon: name })}
                className="inline-flex items-center gap-1 text-xs font-medium text-myco-green hover:underline"
              >
                <Download className="h-3.5 w-3.5" /> CSV for Excel
              </a>
            )}
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {regions.isLoading && <p className="px-4 py-3 text-sm text-muted-foreground">Loading…</p>}
          {regions.isError && (
            <p className="px-4 py-3 text-sm text-muted-foreground">Not available on this server yet.</p>
          )}
          {regions.data && !regions.data.mapped && (
            <p className="border-b px-4 py-2 text-xs text-muted-foreground">
              No map of this taxon has beaten its null models and been counted by state yet, so only
              the states it has been recorded in are listed.
            </p>
          )}
          {rows.length > 0 && (
            <div className="max-h-[420px] overflow-y-auto">
              <table className="w-full text-sm">
                <thead className="sticky top-0 bg-white text-xs uppercase tracking-wider text-muted-foreground">
                  <tr className="border-b">
                    <Th>State or province</Th>
                    <Th right>Records</Th>
                    <Th>Maps say</Th>
                    <Th right>Suitable ground</Th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={`${row.country}:${row.region}`} className="border-b last:border-0">
                      <td className="px-4 py-1.5">
                        {row.region}
                        <span className="ml-1.5 text-xs text-muted-foreground">{row.country}</span>
                      </td>
                      <td className="px-4 py-1.5 text-right tabular-nums">
                        {row.records > 0 ? formatNumber(row.records) : (
                          <span className="text-xs text-muted-foreground">not yet</span>
                        )}
                      </td>
                      <td className="px-4 py-1.5">
                        <span className={`rounded px-1.5 py-0.5 text-xs ${VERDICT_STYLE[row.model]}`}>
                          {VERDICT_LABEL[row.model]}
                        </span>
                      </td>
                      <td
                        className="px-4 py-1.5 text-right tabular-nums text-muted-foreground"
                        title={
                          row.reach_share == null
                            ? undefined
                            : `On average ${percent(row.suitable_share)}; best single map ${percent(row.best_share)}; ` +
                              `${percent(row.reach_share)} of it within the maps' reach`
                        }
                      >
                        {row.model === "possible"
                          ? `${percent(row.best_share)} on one map`
                          : percent(row.suitable_share)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {rows.length > 0 && (
            <div className="space-y-2 border-t border-[#A87146]/10 p-4 text-xs text-muted-foreground">
              <p>
                For a live copy in a spreadsheet, use Excel's Data › From Web, or{" "}
                <code className="rounded bg-muted px-1">=IMPORTDATA("…")</code> in Google Sheets, with this
                link:
              </p>
              <div className="flex items-center gap-2">
                <CodeLine value={csv} />
                <CopyButton text={csv} label="Copy" />
              </div>
              <p>
                Every species in a state or province:{" "}
                <a href="/data#checklists" className="text-myco-green hover:underline">
                  checklists on the Data page
                </a>
                .
              </p>
            </div>
          )}
        </CardContent>
      </Card>
    </section>
  );
}

/**
 * Ways to use a taxon's map outside Atlas: an iframe for a website, and a
 * picture for Excel, a document or a slide.
 */
function UseElsewhere({ name, algorithms }: { name: string; algorithms: Algorithm[] }) {
  const [algorithm, setAlgorithm] = useState<Algorithm | null>(null);
  const [points, setPoints] = useState(true);
  const chosen = algorithm && algorithms.includes(algorithm) ? algorithm : algorithms[0];

  const embed = chosen ? absoluteUrl(embedPath(name, chosen, points)) : "";
  const iframe =
    `<iframe src="${embed}" width="100%" height="450" style="border:0" loading="lazy" ` +
    `title="${name} habitat map, MycoMap Atlas"></iframe>`;
  // The picture's own choice of map when the reader has not picked one, so
  // a pasted link keeps showing the taxon's main map after a refit.
  const picture = absoluteUrl(imageUrl(name, { algorithm: algorithm ?? undefined, points }));
  const formula = `=IMAGE("${picture}")`;

  return (
    <section id="use">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-3">
        <SectionTitle>Use this map elsewhere</SectionTitle>
        <div className="flex flex-wrap items-center gap-4 text-xs text-[#5c4a3a]">
          {algorithms.length > 1 && (
            <label className="inline-flex items-center gap-1.5">
              Model
              <select
                value={chosen}
                onChange={(event) => setAlgorithm(event.target.value as Algorithm)}
                className="rounded border border-[#A87146]/30 bg-white px-1.5 py-1"
              >
                {algorithms.map((a) => (
                  <option key={a} value={a}>
                    {ALGORITHM_LABELS[a]}
                  </option>
                ))}
              </select>
            </label>
          )}
          <label className="inline-flex items-center gap-1.5">
            <input type="checkbox" checked={points} onChange={(event) => setPoints(event.target.checked)} />
            Show collections
          </label>
        </div>
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-2">
            <CardTitle className="text-base text-[#4a3728]">Picture for Excel, Word or slides</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 p-4 text-sm text-[#5c4a3a]">
            <a href={picture} target="_blank" rel="noreferrer" className="block">
              <img
                src={imageUrl(name, { algorithm: algorithm ?? undefined, points, width: 600 })}
                alt={`${name} habitat map`}
                loading="lazy"
                className="w-full rounded border border-[#A87146]/20"
              />
            </a>
            <p>
              In Excel, paste the formula into a cell; it shows the map and fetches it again when the
              sheet refreshes. In Word or slides, download the picture.
            </p>
            <CodeLine value={formula} />
            <div className="flex flex-wrap items-center gap-3">
              <CopyButton text={formula} label="Copy Excel formula" />
              <CopyButton text={picture} label="Copy link" />
              <a
                href={imageUrl(name, { algorithm: algorithm ?? undefined, points, width: 1600 })}
                download={`${name} habitat map.png`}
                className="inline-flex items-center gap-1 text-xs font-medium text-myco-green hover:underline"
              >
                <Download className="h-3.5 w-3.5" /> Download
              </a>
            </div>
          </CardContent>
        </Card>

        {chosen && (
          <Card>
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-2">
              <CardTitle className="text-base text-[#4a3728]">Embed on a website</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 p-4 text-sm text-[#5c4a3a]">
              <p>
                Paste this where your site takes HTML (WordPress, Squarespace, Wix and Google Sites all
                have an embed or HTML block). The map stays live: it updates when the model is refitted,
                and readers can pan and zoom.
              </p>
              <CodeBox value={iframe} />
              <div className="flex flex-wrap items-center gap-3">
                <CopyButton text={iframe} label="Copy embed code" />
                <CopyButton text={embed} label="Copy link" />
                <a
                  href={embed}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1 text-xs font-medium text-myco-green hover:underline"
                >
                  Preview <ExternalLink className="h-3.5 w-3.5" />
                </a>
              </div>
              <p className="text-xs text-muted-foreground">
                Notion and some forum software take the link instead of the code.
              </p>
            </CardContent>
          </Card>
        )}
      </div>
    </section>
  );
}

/** Where a taxon occurs, and ways to take its map elsewhere. */
export function ShareMap({ name, algorithms }: { name: string; algorithms: Algorithm[] }) {
  return (
    <>
      <WhereItOccurs name={name} />
      <UseElsewhere name={name} algorithms={algorithms} />
    </>
  );
}
