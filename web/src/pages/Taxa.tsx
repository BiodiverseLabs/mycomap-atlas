import { useEffect, useState } from "react";
import { useQuery, keepPreviousData } from "@tanstack/react-query";
import { Link, useSearch } from "wouter";

import { ApiDown, Th } from "@/components/Common";
import { Page, PageHeader } from "@/components/Layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getModels, getTaxa, searchTaxa } from "@/lib/api";
import { formatNumber } from "@/lib/utils";

const PAGE_SIZE = 50;
const FILTERS = [0, 5, 10, 20, 30, 50];

export default function Taxa() {
  // ?q= comes from the header search: a genus, or every match for what was typed.
  const urlQuery = new URLSearchParams(useSearch()).get("q") ?? "";
  const [search, setSearch] = useState(urlQuery);
  const [minLocalities, setMinLocalities] = useState(0);
  const [offset, setOffset] = useState(0);
  useEffect(() => {
    setSearch(urlQuery);
    setOffset(0);
  }, [urlQuery]);

  const query = useQuery({
    queryKey: ["taxa", search, minLocalities, offset],
    queryFn: () => getTaxa({ search, minLocalities, limit: PAGE_SIZE, offset }),
    placeholderData: keepPreviousData,
  });
  const models = useQuery({ queryKey: ["models"], queryFn: getModels });
  const mapped = new Set((models.data ?? []).filter((m) => m.map).map((m) => m.taxon));
  const total = query.data?.total ?? 0;
  // The list matches names literally. When that finds nothing, ask the
  // forgiving search what was probably meant.
  const empty = query.data?.total === 0 && search.trim().length >= 2;
  const suggestions = useQuery({
    queryKey: ["search", search.trim(), "suggest"],
    enabled: empty,
    queryFn: () => searchTaxa(search.trim(), 6),
  });

  return (
    <>
      <PageHeader title="Taxa">
        Every name with at least one DNA-validated, well-located record in North America. A map
        needs records from about 20 separate places; below that a taxon is a survey target, and
        each new collection brings it closer.
      </PageHeader>
      <Page>
        {query.isError ? (
          <ApiDown />
        ) : (
          <Card>
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <CardTitle className="text-base text-[#4a3728]">
                  {formatNumber(total)} taxa
                </CardTitle>
                <div className="flex flex-wrap items-center gap-3">
                  <input
                    value={search}
                    onChange={(event) => {
                      setSearch(event.target.value);
                      setOffset(0);
                    }}
                    placeholder="Search names…"
                    className="h-9 w-56 rounded-md border border-input bg-white px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
                  />
                  <label className="flex items-center gap-2 text-sm text-muted-foreground">
                    Localities
                    <select
                      value={minLocalities}
                      onChange={(event) => {
                        setMinLocalities(Number(event.target.value));
                        setOffset(0);
                      }}
                      className="h-9 rounded-md border border-input bg-white px-2 text-sm"
                    >
                      {FILTERS.map((value) => (
                        <option key={value} value={value}>
                          {value === 0 ? "any" : `${value}+`}
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
                    <Th right>Records</Th>
                    <Th right>Localities</Th>
                  </tr>
                </thead>
                <tbody>
                  {query.isLoading && (
                    <tr>
                      <td className="px-4 py-3 text-muted-foreground" colSpan={3}>
                        Loading…
                      </td>
                    </tr>
                  )}
                  {query.data?.items.map((taxon) => (
                    <tr key={taxon.scientific_name} className="border-b last:border-0 hover:bg-myco-green/5">
                      <td className="px-4 py-2">
                        <Link
                          href={`/taxa/${encodeURIComponent(taxon.scientific_name)}`}
                          className="sci text-[#4a3728] hover:text-myco-green"
                        >
                          {taxon.scientific_name}
                        </Link>
                        {mapped.has(taxon.scientific_name) && <Badge className="ml-2">map</Badge>}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatNumber(taxon.records)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatNumber(taxon.localities)}</td>
                    </tr>
                  ))}
                  {query.data?.items.length === 0 && (
                    <tr>
                      <td className="px-4 py-3 text-muted-foreground" colSpan={3}>
                        {suggestions.data?.species.length ? (
                          <>
                            No name contains &ldquo;{search.trim()}&rdquo;. Did you mean{" "}
                            {suggestions.data.species.map((s, i) => (
                              <span key={s.scientific_name}>
                                {i > 0 && ", "}
                                <Link
                                  href={`/taxa/${encodeURIComponent(s.scientific_name)}`}
                                  className="sci text-myco-green hover:underline"
                                >
                                  {s.scientific_name}
                                </Link>
                              </span>
                            ))}
                            ?
                          </>
                        ) : (
                          "Nothing matches that filter."
                        )}
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </CardContent>
          </Card>
        )}

        <div className="flex items-center gap-3 text-sm">
          <Button variant="outline" size="sm" disabled={offset === 0}
                  onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}>
            Previous
          </Button>
          <Button variant="outline" size="sm" disabled={offset + PAGE_SIZE >= total}
                  onClick={() => setOffset(offset + PAGE_SIZE)}>
            Next
          </Button>
          <span className="text-muted-foreground tabular-nums">
            {formatNumber(Math.min(offset + 1, total))}–{formatNumber(Math.min(offset + PAGE_SIZE, total))} of{" "}
            {formatNumber(total)}
          </span>
        </div>
      </Page>
    </>
  );
}
