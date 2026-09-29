import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "wouter";

import { ApiDown, Auc, Loading, Th } from "@/components/Common";
import { Page, PageHeader } from "@/components/Layout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ALGORITHMS, ALGORITHM_LABELS, getModels, type Algorithm, type ModelSummary } from "@/lib/api";
import { formatNumber } from "@/lib/utils";

const PAGE_SIZE = 50;

/** One taxon with whichever of the three models it has. */
interface Row {
  taxon: string;
  presences?: number;
  models: Partial<Record<Algorithm, ModelSummary>>;
}

type Measure = "auc_mean" | "boyce_mean";

function value(row: Row, algorithm: Algorithm, measure: Measure): number {
  return row.models[algorithm]?.[measure] ?? -Infinity;
}

export default function Maps() {
  const models = useQuery({ queryKey: ["models"], queryFn: getModels });
  const [search, setSearch] = useState("");
  const [measure, setMeasure] = useState<Measure>("auc_mean");
  // Most-supported first by default. Sorted by a score, the top of the list is
  // all taxa with barely 20 presence cells, whose scores are the least reliable.
  const [sort, setSort] = useState<string>("presences");
  const [offset, setOffset] = useState(0);

  const rows = useMemo(() => {
    const byTaxon = new Map<string, Row>();
    for (const m of models.data ?? []) {
      if (!m.map) continue;
      const row = byTaxon.get(m.taxon) ?? { taxon: m.taxon, models: {} };
      row.models[m.algorithm] = m;
      row.presences = Math.max(row.presences ?? 0, m.presences ?? 0);
      byTaxon.set(m.taxon, row);
    }
    const needle = search.trim().toLowerCase();
    const matching = [...byTaxon.values()].filter(
      (r) => !needle || r.taxon.toLowerCase().includes(needle),
    );
    const compare =
      sort === "presences"
        ? (a: Row, b: Row) => (b.presences ?? 0) - (a.presences ?? 0)
        : sort === "name"
          ? (a: Row, b: Row) => a.taxon.localeCompare(b.taxon)
          : (a: Row, b: Row) => value(b, sort as Algorithm, measure) - value(a, sort as Algorithm, measure);
    return matching.sort(compare);
  }, [models.data, search, sort, measure]);
  const page = rows.slice(offset, offset + PAGE_SIZE);
  const measureLabel = measure === "auc_mean" ? "AUC" : "Boyce";

  return (
    <>
      <PageHeader title="Maps">
        Every taxon with a fitted habitat map, and how each of the three models scores it on
        regions it never saw. Blocked AUC says how well a map tells this fungus apart from
        everywhere else fungi get collected: 0.5 is chance, and a species that grows wherever people
        look sits near it by nature. Boyce asks whether places a map rates higher really hold more
        records.
      </PageHeader>
      <Page>
        {models.isError && <ApiDown />}
        {models.isLoading && <Loading />}
        {models.data && (
          <Card>
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <CardTitle className="text-base text-[#4a3728]">
                  {formatNumber(rows.length)} taxa mapped
                </CardTitle>
                <div className="flex flex-wrap items-center gap-3">
                  <input
                    value={search}
                    onChange={(event) => {
                      setSearch(event.target.value);
                      setOffset(0);
                    }}
                    placeholder="Filter by name…"
                    className="h-9 w-52 rounded-md border border-input bg-white px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
                  />
                  <label className="flex items-center gap-2 text-sm text-muted-foreground">
                    Score
                    <select
                      value={measure}
                      onChange={(event) => setMeasure(event.target.value as Measure)}
                      className="h-9 rounded-md border border-input bg-white px-2 text-sm"
                    >
                      <option value="auc_mean">Blocked AUC</option>
                      <option value="boyce_mean">Blocked Boyce</option>
                    </select>
                  </label>
                  <label className="flex items-center gap-2 text-sm text-muted-foreground">
                    Sort by
                    <select
                      value={sort}
                      onChange={(event) => {
                        setSort(event.target.value);
                        setOffset(0);
                      }}
                      className="h-9 rounded-md border border-input bg-white px-2 text-sm"
                    >
                      <option value="presences">Presence cells</option>
                      {ALGORITHMS.map((a) => (
                        <option key={a} value={a}>
                          {ALGORITHM_LABELS[a]} {measureLabel}
                        </option>
                      ))}
                      <option value="name">Name</option>
                    </select>
                  </label>
                </div>
              </div>
            </CardHeader>
            <CardContent className="p-0 overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-xs uppercase tracking-wider text-muted-foreground">
                  <tr className="border-b">
                    <Th>Taxon</Th>
                    <Th right>Presence cells</Th>
                    {ALGORITHMS.map((a) => (
                      <Th key={a} right>
                        {ALGORITHM_LABELS[a]}
                      </Th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {page.map((row) => (
                    <tr key={row.taxon} className="border-b last:border-0 hover:bg-myco-green/5">
                      <td className="px-4 py-2">
                        <Link
                          href={`/taxa/${encodeURIComponent(row.taxon)}`}
                          className="sci text-[#4a3728] hover:text-myco-green"
                        >
                          {row.taxon}
                        </Link>
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatNumber(row.presences)}</td>
                      {ALGORITHMS.map((a) => {
                        const m = row.models[a];
                        return (
                          <td key={a} className="px-4 py-2 text-right">
                            {!m ? (
                              <span className="text-muted-foreground">—</span>
                            ) : measure === "auc_mean" ? (
                              <Auc value={m.auc_mean} />
                            ) : (
                              <span className="tabular-nums">
                                {m.boyce_mean == null ? "—" : m.boyce_mean.toFixed(2)}
                              </span>
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                  {!page.length && (
                    <tr>
                      <td colSpan={2 + ALGORITHMS.length} className="px-4 py-3 text-muted-foreground">
                        No map matches that name.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </CardContent>
          </Card>
        )}
        {rows.length > PAGE_SIZE && (
          <div className="flex items-center gap-3 text-sm">
            <Button variant="outline" size="sm" disabled={offset === 0}
                    onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}>
              Previous
            </Button>
            <Button variant="outline" size="sm" disabled={offset + PAGE_SIZE >= rows.length}
                    onClick={() => setOffset(offset + PAGE_SIZE)}>
              Next
            </Button>
            <span className="text-muted-foreground tabular-nums">
              {formatNumber(offset + 1)}–{formatNumber(Math.min(offset + PAGE_SIZE, rows.length))} of{" "}
              {formatNumber(rows.length)}
            </span>
          </div>
        )}
      </Page>
    </>
  );
}
