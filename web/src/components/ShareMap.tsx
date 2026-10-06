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
  type Algorithm,
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

/**
 * Ways to use a taxon's map and records outside Atlas: an iframe for a
 * website, and the states and provinces it has been recorded in as a CSV for
 * a spreadsheet.
 */
export function ShareMap({ name, algorithms }: { name: string; algorithms: Algorithm[] }) {
  const [algorithm, setAlgorithm] = useState<Algorithm | null>(null);
  const [points, setPoints] = useState(true);
  const chosen = algorithm && algorithms.includes(algorithm) ? algorithm : algorithms[0];
  const regions = useQuery({ queryKey: ["taxon-regions", name], queryFn: () => getTaxonRegions(name) });

  const embed = chosen ? absoluteUrl(embedPath(name, chosen, points)) : "";
  const iframe =
    `<iframe src="${embed}" width="100%" height="450" style="border:0" loading="lazy" ` +
    `title="${name} habitat map, MycoMap Atlas"></iframe>`;
  const csv = absoluteUrl(checklistUrl({ taxon: name }));
  // Where it is best recorded first.
  const rows = [...(regions.data?.regions ?? [])].sort(
    (a, b) => b.records - a.records || a.region.localeCompare(b.region),
  );

  return (
    <section id="use">
      <SectionTitle>Use this map elsewhere</SectionTitle>
      <div className="grid gap-4 lg:grid-cols-2">
        {chosen && (
          <Card>
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-2">
              <CardTitle className="text-base text-[#4a3728]">Embed on a website</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 p-4 text-sm text-[#5c4a3a]">
              <p>
                Paste this where your site takes HTML (WordPress, Squarespace, Wix and Google Sites
                all have an embed or HTML block). The map stays live: it updates when the model is
                refitted.
              </p>
              <div className="flex flex-wrap items-center gap-4 text-xs">
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

        <Card>
          <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-2">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <CardTitle className="text-base text-[#4a3728]">Recorded in</CardTitle>
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
            {rows.length > 0 && (
              <div className="max-h-[300px] overflow-y-auto">
                <table className="w-full text-sm">
                  <thead className="sticky top-0 bg-white text-xs uppercase tracking-wider text-muted-foreground">
                    <tr className="border-b">
                      <Th>State or province</Th>
                      <Th right>Records</Th>
                      <Th right>Localities</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((row) => (
                      <tr key={`${row.country}:${row.region}`} className="border-b last:border-0">
                        <td className="px-4 py-1.5">
                          {row.region}
                          <span className="ml-1.5 text-xs text-muted-foreground">{row.country}</span>
                        </td>
                        <td className="px-4 py-1.5 text-right tabular-nums">{formatNumber(row.records)}</td>
                        <td className="px-4 py-1.5 text-right tabular-nums">{formatNumber(row.localities)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {rows.length > 0 && (
              <div className="space-y-2 border-t border-[#A87146]/10 p-4 text-xs text-muted-foreground">
                <p>
                  DNA-validated records only, so a state missing here may still have the species,
                  unsequenced. For a live copy in a spreadsheet, use Excel's Data › From Web, or{" "}
                  <code className="rounded bg-muted px-1">=IMPORTDATA("…")</code> in Google Sheets, with
                  this link:
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
      </div>
    </section>
  );
}
