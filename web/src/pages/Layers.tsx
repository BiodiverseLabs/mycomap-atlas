import { useQuery } from "@tanstack/react-query";

import { getLayers } from "@/lib/api";
import { formatNumber, formatWhen } from "@/lib/utils";

export default function Layers() {
  const query = useQuery({ queryKey: ["layers"], queryFn: () => getLayers("draft") });

  if (query.isError) {
    return (
      <div className="rounded-lg border border-border bg-card p-6">
        <h1 className="text-lg font-semibold">The API is not answering</h1>
        <pre className="mt-3 rounded-md bg-muted p-3 text-sm">./atlas api</pre>
      </div>
    );
  }

  const layers = query.data?.layers ?? [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Environmental layers</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Every layer covers all of North America on an equal-area grid, so a
          cell means the same area in Oaxaca and in Nunavut. The draft grid is
          5 km, for developing the pipeline; releases are built at 1 km.
        </p>
      </div>

      <div className="space-y-4">
        {query.isLoading && <p className="text-muted-foreground">Loading…</p>}

        {layers.map((layer) => (
          <div key={layer.id} className="rounded-lg border border-border bg-card p-4">
            <div className="flex flex-wrap items-baseline gap-3">
              <h2 className="font-semibold">{layer.title}</h2>
              <span
                className={
                  layer.built
                    ? "rounded-full bg-primary/15 px-2 py-0.5 text-xs font-medium text-primary"
                    : "rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground"
                }
              >
                {layer.built ? "built" : "not built"}
              </span>
              {layer.built && (
                <span className="text-sm text-muted-foreground lining-nums">
                  {formatNumber(layer.bands?.length)} band
                  {layer.bands?.length === 1 ? "" : "s"} · {layer.sizeMb} MB ·{" "}
                  {formatNumber(layer.cellSizeM)} m cells · {formatWhen(layer.builtAt)}
                </span>
              )}
            </div>

            <p className="mt-2 text-sm text-muted-foreground">
              {layer.source} · {layer.license}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">{layer.citation}</p>
            {layer.note && (
              <p className="mt-2 text-xs text-secondary">{layer.note}</p>
            )}

            {layer.bands && layer.bands.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-1">
                {layer.bands.map((band) => (
                  <span
                    key={band}
                    className="rounded border border-border px-1.5 py-0.5 text-xs text-muted-foreground"
                  >
                    {band}
                  </span>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      <p className="text-xs text-muted-foreground">
        No continental tree-species layer exists, so tree cover is carried as a
        fraction rather than host identity. Host maps are a later refinement,
        region by region.
      </p>
    </div>
  );
}
