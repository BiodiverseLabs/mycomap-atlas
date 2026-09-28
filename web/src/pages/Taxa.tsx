import { useState } from "react";
import { useQuery, keepPreviousData } from "@tanstack/react-query";
import { Link } from "wouter";

import { getTaxa } from "@/lib/api";
import { formatNumber } from "@/lib/utils";

const PAGE_SIZE = 50;
const FILTERS = [0, 5, 10, 20, 30, 50];

export default function Taxa() {
  const [search, setSearch] = useState("");
  const [minLocalities, setMinLocalities] = useState(20);
  const [offset, setOffset] = useState(0);

  const query = useQuery({
    queryKey: ["taxa", search, minLocalities, offset],
    queryFn: () => getTaxa({ search, minLocalities, limit: PAGE_SIZE, offset }),
    placeholderData: keepPreviousData,
  });

  const total = query.data?.total ?? 0;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Taxa</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Every taxon in the validated universe, with the number of independent
          localities that decides whether it can be modelled.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <input
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setOffset(0);
          }}
          placeholder="Search names…"
          className="h-9 w-64 rounded-md border border-input bg-background px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
        />
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          Localities
          <select
            value={minLocalities}
            onChange={(event) => {
              setMinLocalities(Number(event.target.value));
              setOffset(0);
            }}
            className="h-9 rounded-md border border-input bg-background px-2 text-sm"
          >
            {FILTERS.map((value) => (
              <option key={value} value={value}>
                {value === 0 ? "any" : `${value}+`}
              </option>
            ))}
          </select>
        </label>
        <span className="text-sm text-muted-foreground lining-nums">
          {formatNumber(total)} taxa
        </span>
      </div>

      <div className="overflow-hidden rounded-lg border border-border bg-card">
        <table className="w-full text-sm">
          <thead className="border-b border-border text-left text-muted-foreground">
            <tr>
              <th className="px-4 py-2 font-medium">Name</th>
              <th className="px-4 py-2 font-medium">Records</th>
              <th className="px-4 py-2 font-medium">Localities</th>
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
            {query.isError && (
              <tr>
                <td className="px-4 py-3 text-destructive" colSpan={3}>
                  The API is not answering. Start it with{" "}
                  <code className="rounded bg-muted px-1">./atlas api</code>.
                </td>
              </tr>
            )}
            {query.data?.items.map((taxon) => (
              <tr key={taxon.scientific_name} className="border-b border-border last:border-0">
                <td className="px-4 py-2">
                  <Link
                    href={`/taxa/${encodeURIComponent(taxon.scientific_name)}`}
                    className="font-species text-foreground hover:text-primary"
                  >
                    {taxon.scientific_name}
                  </Link>
                </td>
                <td className="px-4 py-2 lining-nums">{formatNumber(taxon.records)}</td>
                <td className="px-4 py-2 lining-nums">{formatNumber(taxon.localities)}</td>
              </tr>
            ))}
            {query.data?.items.length === 0 && (
              <tr>
                <td className="px-4 py-3 text-muted-foreground" colSpan={3}>
                  Nothing matches that filter.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center gap-3 text-sm">
        <button
          type="button"
          disabled={offset === 0}
          onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}
          className="rounded-md border border-border px-3 py-1.5 disabled:opacity-40"
        >
          Previous
        </button>
        <button
          type="button"
          disabled={offset + PAGE_SIZE >= total}
          onClick={() => setOffset(offset + PAGE_SIZE)}
          className="rounded-md border border-border px-3 py-1.5 disabled:opacity-40"
        >
          Next
        </button>
        <span className="text-muted-foreground lining-nums">
          {formatNumber(Math.min(offset + PAGE_SIZE, total))} of {formatNumber(total)}
        </span>
      </div>
    </div>
  );
}
