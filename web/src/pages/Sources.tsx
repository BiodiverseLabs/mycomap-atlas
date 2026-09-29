import type { ReactNode } from "react";
import { ArrowUpRight } from "lucide-react";

import { GithubMark } from "@/components/Common";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Card, CardContent } from "@/components/ui/card";
import { GITHUB_URL, SOURCES, type Availability, type Software } from "@/lib/contract";

function Ext({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="inline-flex items-center gap-0.5 text-myco-green hover:underline"
    >
      {children}
      <ArrowUpRight className="h-3 w-3" />
    </a>
  );
}

const doiUrl = (doi: string) => `https://doi.org/${doi}`;

const AVAILABILITY: Record<Availability, { label: string; tone: string }> = {
  published: { label: "Published", tone: "bg-myco-green/15 text-[#2e5a17] border-myco-green/30" },
  "in releases": { label: "In releases", tone: "bg-myco-green/5 text-[#2e5a17] border-myco-green/30" },
  planned: { label: "Planned", tone: "bg-[#f3e6d6] text-[#7a4e2c] border-[#A87146]/30" },
  "at source": { label: "At the source", tone: "bg-white text-[#5c4a3a] border-[#A87146]/30" },
  withheld: { label: "Never published", tone: "bg-[#4a3728] text-white border-[#4a3728]" },
};

function AvailabilityBadge({ value }: { value: Availability }) {
  const { label, tone } = AVAILABILITY[value];
  return (
    <span className={`inline-block whitespace-nowrap rounded-full border px-2 py-0.5 text-xs font-semibold ${tone}`}>
      {label}
    </span>
  );
}

/** Route names in a product's "where" become links to the Developers page. */
function Where({ text }: { text: string }) {
  const parts = text.split(/(\/api\/[A-Za-z{}/.]+)/g);
  return (
    <>
      {parts.map((part, i) =>
        part.startsWith("/api/") ? (
          <a key={i} href="/developers" className="font-mono text-xs text-myco-green hover:underline">
            {part}
          </a>
        ) : (
          <span key={i}>{part}</span>
        ),
      )}
    </>
  );
}

const GROUPS: { id: Software["group"]; title: string; note: string }[] = [
  { id: "r", title: "Modelling (R packages)", note: "Pinned in the release container, so a map can be rebuilt exactly." },
  { id: "platform", title: "Platform", note: "" },
  { id: "web", title: "This website", note: "" },
];

export default function Sources() {
  const stages = [...new Set(SOURCES.products.map((p) => p.stage))];

  return (
    <>
      <PageHeader title="Data and sources">
        Everything Atlas is built on, with a link to each: the records and environmental datasets,
        every software package, the papers behind each method — and every file the pipeline makes
        along the way, with whether you can get it and where.
      </PageHeader>
      <Page>
        <section>
          <SectionTitle>Datasets</SectionTitle>
          <div className="grid gap-4 md:grid-cols-2">
            {SOURCES.datasets.map((d) => (
              <Card key={d.id}>
                <CardContent className="space-y-2 p-5 text-sm">
                  <div>
                    <h3 className="font-semibold text-[#4a3728]">{d.name}</h3>
                    {d.provider && <div className="text-xs text-muted-foreground">{d.provider}</div>}
                  </div>
                  <p className="text-[#5c4a3a] leading-relaxed">{d.role}</p>
                  {d.citation && <p className="text-xs text-muted-foreground leading-relaxed">{d.citation}</p>}
                  <div className="flex flex-wrap gap-x-4 gap-y-1 pt-1">
                    <Ext href={d.url}>Website</Ext>
                    {d.doi && <Ext href={doiUrl(d.doi)}>doi:{d.doi}</Ext>}
                    {d.license_url ? (
                      <Ext href={d.license_url}>{d.license}</Ext>
                    ) : (
                      <span className="text-xs text-muted-foreground">{d.license}</span>
                    )}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>

        <section>
          <SectionTitle>Every layer of the analysis</SectionTitle>
          <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
            What each stage of the pipeline produces, from the records to the published release.
            The goal is that anyone can pick the analysis up at any stage: rerun a model on the same
            training table, fit a new one on the same layers, or check a map against its scores.
            The one thing that is never published is where a collection was made more precisely than
            0.1°.
          </p>
          <Card>
            <CardContent className="p-0 overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-xs uppercase tracking-wider text-muted-foreground">
                  <tr className="border-b">
                    <th className="px-4 py-2 text-left font-medium">Stage</th>
                    <th className="px-4 py-2 text-left font-medium">Product</th>
                    <th className="px-4 py-2 text-left font-medium">Available</th>
                    <th className="px-4 py-2 text-left font-medium">Where, or why not yet</th>
                  </tr>
                </thead>
                <tbody>
                  {stages.map((stage) =>
                    SOURCES.products
                      .filter((p) => p.stage === stage)
                      .map((p, i, rows) => (
                        <tr key={p.name} className="border-b last:border-0 align-top">
                          {i === 0 && (
                            <td rowSpan={rows.length} className="px-4 py-3 font-semibold text-[#4a3728] whitespace-nowrap">
                              {stage}
                            </td>
                          )}
                          <td className="px-4 py-3">
                            <div className="font-medium text-[#4a3728]">{p.name}</div>
                            <div className="text-xs text-[#5c4a3a] leading-relaxed">{p.detail}</div>
                          </td>
                          <td className="px-4 py-3">
                            <AvailabilityBadge value={p.availability} />
                          </td>
                          <td className="px-4 py-3 text-xs text-[#5c4a3a] leading-relaxed">
                            <Where text={p.where ?? p.why ?? ""} />
                          </td>
                        </tr>
                      )),
                  )}
                </tbody>
              </table>
            </CardContent>
          </Card>
        </section>

        <section>
          <SectionTitle>Software</SectionTitle>
          <div className="grid gap-4 lg:grid-cols-3">
            {GROUPS.map((group) => (
              <Card key={group.id}>
                <CardContent className="p-5">
                  <h3 className="font-semibold text-[#4a3728]">{group.title}</h3>
                  {group.note && <p className="mt-1 text-xs text-muted-foreground">{group.note}</p>}
                  <ul className="mt-3 space-y-3 text-sm">
                    {SOURCES.software
                      .filter((s) => s.group === group.id)
                      .map((s) => (
                        <li key={s.name}>
                          <div className="flex flex-wrap items-baseline justify-between gap-x-2">
                            <Ext href={s.url}>
                              <span className="font-mono text-[13px]">{s.name}</span>
                            </Ext>
                            <span className="text-xs text-muted-foreground">{s.license}</span>
                          </div>
                          <div className="text-xs text-[#5c4a3a] leading-relaxed">{s.role}</div>
                          {s.doi && (
                            <div className="text-xs">
                              <Ext href={doiUrl(s.doi)}>Cite: doi:{s.doi}</Ext>
                            </div>
                          )}
                        </li>
                      ))}
                  </ul>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>

        <section>
          <SectionTitle>Methods literature</SectionTitle>
          <ul className="max-w-4xl space-y-3 text-sm">
            {SOURCES.references.map((r) => (
              <li key={r.citation} className="border-l-2 border-myco-green/40 pl-3">
                <div className="text-[#4a3728] leading-relaxed">
                  {r.citation} {r.doi && <Ext href={doiUrl(r.doi)}>doi:{r.doi}</Ext>}
                </div>
                <div className="text-xs text-muted-foreground">Used for: {r.used_for}</div>
              </li>
            ))}
          </ul>
        </section>

        <section className="max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
          <p>
            This page is drawn from <code>inst/api/sources.json</code>, which the API also serves at{" "}
            <a href="/developers#getSources" className="text-myco-green hover:underline">/api/sources</a>. A
            test fails when the code starts calling a package, or the website starts depending on one,
            that is not credited here.{" "}
            <a href={GITHUB_URL} className="inline-flex items-center gap-1 text-myco-green hover:underline">
              <GithubMark className="h-3.5 w-3.5" /> Source code
            </a>
          </p>
        </section>
      </Page>
    </>
  );
}
