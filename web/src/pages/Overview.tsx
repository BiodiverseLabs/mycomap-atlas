import { useQuery } from "@tanstack/react-query";

import { getStatus, getTaxaCount } from "@/lib/api";
import { formatNumber, formatWhen } from "@/lib/utils";

// 20 localities is the phase 1 publishing threshold: below it a model is not
// published and the taxon is listed as a survey target instead.
const THRESHOLDS = [5, 10, 20, 30, 50, 100];
const PUBLISH_AT = 20;

function Card({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <div className="text-xs uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className="mt-1 text-2xl font-semibold lining-nums">{value}</div>
    </div>
  );
}

export default function Overview() {
  const status = useQuery({ queryKey: ["status"], queryFn: getStatus });

  const readiness = useQuery({
    queryKey: ["readiness"],
    enabled: status.data?.ready === true,
    queryFn: async () =>
      Promise.all(
        THRESHOLDS.map(async (threshold) => ({
          threshold,
          taxa: await getTaxaCount(threshold),
        })),
      ),
  });

  if (status.isLoading) {
    return <p className="text-muted-foreground">Loading…</p>;
  }

  if (status.isError) {
    return (
      <div className="rounded-lg border border-border bg-card p-6">
        <h1 className="text-lg font-semibold">The API is not answering</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Start it from the repository root, then reload:
        </p>
        <pre className="mt-3 rounded-md bg-muted p-3 text-sm">./atlas api</pre>
      </div>
    );
  }

  if (!status.data?.ready) {
    return (
      <div className="rounded-lg border border-border bg-card p-6">
        <h1 className="text-lg font-semibold">Nothing pulled yet</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Pull the validated training universe from mycomap.org, then reload:
        </p>
        <pre className="mt-3 rounded-md bg-muted p-3 text-sm">./atlas pull-occurrences</pre>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Training universe</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Records mycomap.org has validated by DNA, with coordinates good enough
          for a 1 km model, in North America.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card label="Records" value={formatNumber(status.data.records)} />
        <Card label="Taxa" value={formatNumber(status.data.taxa)} />
        <Card label="Last pull" value={formatWhen(status.data.pulledAt)} />
        <Card
          label="Fingerprint"
          value={status.data.fingerprint?.slice(0, 12) ?? "—"}
        />
      </div>

      <section className="rounded-lg border border-border bg-card">
        <div className="border-b border-border px-4 py-3">
          <h2 className="font-semibold">Modelable taxa</h2>
          <p className="text-sm text-muted-foreground">
            Counted as distinct localities about 1 km apart. Phase 1 publishes a
            map at {PUBLISH_AT} or more; below that the taxon becomes a survey
            target.
          </p>
        </div>
        <table className="w-full text-sm">
          <thead className="text-left text-muted-foreground">
            <tr>
              <th className="px-4 py-2 font-medium">Localities</th>
              <th className="px-4 py-2 font-medium">Taxa</th>
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
                className={row.threshold === PUBLISH_AT ? "bg-accent/60" : undefined}
              >
                <td className="px-4 py-2">{row.threshold} or more</td>
                <td className="px-4 py-2 lining-nums">{formatNumber(row.taxa)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className="rounded-lg border border-border bg-card p-4 text-sm text-muted-foreground">
        <h2 className="font-semibold text-foreground">What happens next</h2>
        <ol className="mt-2 list-decimal space-y-1 pl-5">
          <li>Environmental layers for the region, versioned.</li>
          <li>
            A target-group background drawn from this same universe, so models
            learn habitat rather than where sequencing happened.
          </li>
          <li>Maxent fits, with boosted trees as the benchmark on the richest taxa.</li>
          <li>Spatially blocked evaluation, then published maps and metrics.</li>
        </ol>
      </section>
    </div>
  );
}
