import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "wouter";

import { ApiDown, Auc, Loading, Th } from "@/components/Common";
import { Page, PageHeader } from "@/components/Layout";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getModels, type ModelSummary } from "@/lib/api";
import { formatNumber, formatWhen } from "@/lib/utils";

const PAGE_SIZE = 50;

// Most-supported first by default. Sorted by AUC, the top of the list is all
// taxa with barely 20 presence cells, whose scores are the least reliable.
const SORTS: Record<string, { label: string; compare: (a: ModelSummary, b: ModelSummary) => number }> = {
  presences: { label: "Presence cells", compare: (a, b) => (b.presences ?? 0) - (a.presences ?? 0) },
  auc: { label: "Blocked AUC", compare: (a, b) => (b.auc_mean ?? -1) - (a.auc_mean ?? -1) },
  name: { label: "Name", compare: (a, b) => a.taxon.localeCompare(b.taxon) },
  built: { label: "Newest", compare: (a, b) => b.built_at.localeCompare(a.built_at) },
};

export default function Maps() {
  const models = useQuery({ queryKey: ["models"], queryFn: getModels });
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState("presences");
  const [offset, setOffset] = useState(0);

  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    const matching = (models.data ?? []).filter(
      (m) => m.map && (!needle || m.taxon.toLowerCase().includes(needle)),
    );
    return [...matching].sort(SORTS[sort].compare);
  }, [models.data, search, sort]);
  const page = rows.slice(offset, offset + PAGE_SIZE);

  return (
    <>
      <PageHeader title="Maps">
        Every taxon with a fitted habitat map. Blocked AUC says how well a map tells this fungus
        apart from everywhere else fungi get collected, scored on regions the model never saw:
        0.5 is no better than chance, and a species that grows wherever people look sits near it
        by nature.
      </PageHeader>
      <Page>
        {models.isError && <ApiDown />}
        {models.isLoading && <Loading />}
        {models.data && (
          <Card>
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <CardTitle className="text-base text-[#4a3728]">
                  {formatNumber(rows.length)} maps
                </CardTitle>
                <div className="flex flex-wrap items-center gap-3">
                  <input
                    value={search}
                    onChange={(event) => {
                      setSearch(event.target.value);
                      setOffset(0);
                    }}
                    placeholder="Filter by name…"
                    className="h-9 w-56 rounded-md border border-input bg-white px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
                  />
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
                      {Object.entries(SORTS).map(([key, { label }]) => (
                        <option key={key} value={key}>
                          {label}
                        </option>
                      ))}
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
                    <Th right>Predictors</Th>
                    <Th right>Blocked AUC</Th>
                    <Th right>Boyce</Th>
                    <Th right>Fitted</Th>
                  </tr>
                </thead>
                <tbody>
                  {page.map((m) => (
                    <tr key={m.taxon} className="border-b last:border-0 hover:bg-myco-green/5">
                      <td className="px-4 py-2">
                        <Link
                          href={`/taxa/${encodeURIComponent(m.taxon)}`}
                          className="sci text-[#4a3728] hover:text-myco-green"
                        >
                          {m.taxon}
                        </Link>
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatNumber(m.presences)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatNumber(m.predictors)}</td>
                      <td className="px-4 py-2 text-right">
                        <Auc value={m.auc_mean} />
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">
                        {m.boyce_mean == null ? "—" : m.boyce_mean.toFixed(2)}
                      </td>
                      <td className="px-4 py-2 text-right text-muted-foreground whitespace-nowrap">
                        {formatWhen(m.built_at).split(",")[0]}
                      </td>
                    </tr>
                  ))}
                  {!page.length && (
                    <tr>
                      <td colSpan={6} className="px-4 py-3 text-muted-foreground">
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
