import { useQuery } from "@tanstack/react-query";

import { ApiDown, Loading, Stat, Th } from "@/components/Common";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ALGORITHMS,
  ALGORITHM_LABELS,
  ALGORITHM_NOTES,
  getBenchmark,
  getModels,
  type Algorithm,
  type Benchmark,
  type BenchmarkRow,
  type ModelSummary,
} from "@/lib/api";
import { formatNumber, formatWhen } from "@/lib/utils";

/** An arm is a model, or a model given Maxent's predictors. */
function armLabel(arm: string): string {
  const base = arm.replace(/-pruned$/, "") as Algorithm;
  const label = ALGORITHM_LABELS[base] ?? arm;
  return arm.endsWith("-pruned") ? `${label} (Maxent's variables)` : label;
}

function median(values: number[]): number | undefined {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return undefined;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function fixed(value: number | undefined, digits = 3) {
  return value == null || !Number.isFinite(value) ? "—" : value.toFixed(digits);
}

/** A paired difference from Maxent, marked when it is more than two standard errors. */
function Delta({ value, se, baseline }: { value?: number; se?: number; baseline: boolean }) {
  if (baseline) return <span className="text-muted-foreground">baseline</span>;
  if (value == null || !Number.isFinite(value)) return <span className="text-muted-foreground">—</span>;
  const clear = se != null && se > 0 && Math.abs(value) > 2 * se;
  const tone = clear ? (value > 0 ? "text-myco-green font-semibold" : "text-destructive font-semibold") : "";
  return (
    <span className={`tabular-nums whitespace-nowrap ${tone}`}>
      {value > 0 ? "+" : ""}
      {value.toFixed(3)}
      {se != null && Number.isFinite(se) && (
        <span className="ml-1 font-normal text-muted-foreground">± {se.toFixed(3)}</span>
      )}
    </span>
  );
}

function SummaryTable({ rows, benchmark }: { rows: BenchmarkRow[]; benchmark: Benchmark }) {
  const seconds = (arm: string) => {
    const values = benchmark.taxa.flatMap((t) =>
      (t.arms ?? []).filter((a) => a.arm === arm && a.seconds != null).map((a) => a.seconds!),
    );
    return median(values);
  };
  return (
    <table className="w-full text-sm">
      <thead className="text-xs uppercase tracking-wider text-muted-foreground">
        <tr className="border-b">
          <Th>Model</Th>
          <Th right>Taxa</Th>
          <Th right>Mean AUC</Th>
          <Th right>AUC vs Maxent</Th>
          <Th right>Mean Boyce</Th>
          <Th right>Boyce vs Maxent</Th>
          <Th right>Best AUC</Th>
          <Th right>Scoring time</Th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => {
          const isBase = row.arm === benchmark.baseline;
          return (
            <tr key={row.arm} className="border-b last:border-0">
              <td className="px-4 py-2 text-[#4a3728] font-medium">{armLabel(row.arm)}</td>
              <td className="px-4 py-2 text-right tabular-nums">{formatNumber(row.taxa)}</td>
              <td className="px-4 py-2 text-right tabular-nums">{fixed(row.auc)}</td>
              <td className="px-4 py-2 text-right">
                <Delta value={row.delta_auc} se={row.delta_se} baseline={isBase} />
              </td>
              <td className="px-4 py-2 text-right tabular-nums">{fixed(row.boyce)}</td>
              <td className="px-4 py-2 text-right">
                <Delta value={row.delta_boyce} se={row.delta_boyce_se} baseline={isBase} />
              </td>
              <td className="px-4 py-2 text-right tabular-nums">
                {row.best_share == null ? "—" : `${Math.round(row.best_share * 100)}%`}
              </td>
              <td className="px-4 py-2 text-right tabular-nums text-muted-foreground">
                {seconds(row.arm) == null ? "—" : `${seconds(row.arm)!.toFixed(0)} s`}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function BenchmarkSection({ benchmark }: { benchmark: Benchmark }) {
  const scored = benchmark.taxa.filter((t) => t.status === "scored").length;
  const bands = [...new Set(benchmark.summary.map((r) => r.band))].filter((b) => b !== "all");
  const overall = benchmark.summary.filter((r) => r.band === "all");
  return (
    <section>
      <SectionTitle>Benchmark</SectionTitle>
      <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
        Every taxon with 50 or more presence cells, scored by each model on exactly the same
        training records, background and {benchmark.settings.folds ?? 5} spatial folds of{" "}
        {formatNumber(Number(benchmark.settings.block_km ?? 200))} km. Differences are paired — each
        taxon against itself — and shown with their standard error; a difference is marked when it
        is larger than two standard errors, green if better than Maxent and red if worse.
      </p>
      <Card>
        <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <CardTitle className="text-base text-[#4a3728]">All taxa</CardTitle>
            <span className="text-xs text-muted-foreground">
              {formatNumber(scored)} taxa scored · started {formatWhen(benchmark.started_at)}
            </span>
          </div>
        </CardHeader>
        <CardContent className="p-0 overflow-x-auto">
          <SummaryTable rows={overall} benchmark={benchmark} />
        </CardContent>
      </Card>

      <div className="mt-6 space-y-4">
        {bands.map((band) => (
          <Card key={band}>
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-2">
              <CardTitle className="text-sm text-[#4a3728]">{band} presence cells</CardTitle>
            </CardHeader>
            <CardContent className="p-0 overflow-x-auto">
              <SummaryTable rows={benchmark.summary.filter((r) => r.band === band)} benchmark={benchmark} />
            </CardContent>
          </Card>
        ))}
      </div>
    </section>
  );
}

function ProductionSection({ models }: { models: ModelSummary[] }) {
  return (
    <section>
      <SectionTitle>Maps in the app</SectionTitle>
      <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
        How many taxa each model has mapped, and the median of their blocked scores. These cover
        every taxon with 20 or more presence cells, so they run lower than the benchmark, which
        only includes the richest.
      </p>
      <div className="grid gap-4 md:grid-cols-3">
        {ALGORITHMS.map((algorithm) => {
          const mine = models.filter((m) => m.algorithm === algorithm && m.map);
          return (
            <Card key={algorithm}>
              <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
                <CardTitle className="text-base text-[#4a3728]">{ALGORITHM_LABELS[algorithm]}</CardTitle>
              </CardHeader>
              <CardContent className="p-4 space-y-3">
                <div className="grid grid-cols-3 gap-2 text-center">
                  <div>
                    <div className="text-xs uppercase tracking-wider text-muted-foreground">Maps</div>
                    <div className="text-xl font-semibold text-[#4a3728] tabular-nums">
                      {formatNumber(mine.length)}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs uppercase tracking-wider text-muted-foreground">AUC</div>
                    <div className="text-xl font-semibold text-[#4a3728] tabular-nums">
                      {fixed(median(mine.map((m) => m.auc_mean ?? NaN)), 2)}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs uppercase tracking-wider text-muted-foreground">Boyce</div>
                    <div className="text-xl font-semibold text-[#4a3728] tabular-nums">
                      {fixed(median(mine.map((m) => m.boyce_mean ?? NaN)), 2)}
                    </div>
                  </div>
                </div>
                <p className="text-sm text-[#5c4a3a] leading-relaxed">{ALGORITHM_NOTES[algorithm]}</p>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </section>
  );
}

export default function Models() {
  const benchmark = useQuery({ queryKey: ["benchmark"], queryFn: getBenchmark });
  const models = useQuery({ queryKey: ["models"], queryFn: getModels });

  return (
    <>
      <PageHeader title="Models">
        Every map is drawn three ways — Maxent, boosted trees and a random forest — from the same
        records against the same background. None is right by default; comparing them shows where
        they agree, and where a map says more about the model than about the fungus.
      </PageHeader>
      <Page>
        {(benchmark.isError || models.isError) && <ApiDown />}
        {models.data && (
          <div className="grid gap-4 sm:grid-cols-3">
            {ALGORITHMS.map((a) => (
              <Stat
                key={a}
                label={`${ALGORITHM_LABELS[a]} maps`}
                value={formatNumber(models.data.filter((m) => m.algorithm === a && m.map).length)}
              />
            ))}
          </div>
        )}
        {benchmark.isLoading && <Loading />}
        {benchmark.data && <BenchmarkSection benchmark={benchmark.data} />}
        {benchmark.data === null && (
          <p className="text-sm text-muted-foreground">
            No benchmark yet. Run <code className="rounded bg-muted px-1">./atlas benchmark-models</code>.
          </p>
        )}
        {models.data && <ProductionSection models={models.data} />}
      </Page>
    </>
  );
}
