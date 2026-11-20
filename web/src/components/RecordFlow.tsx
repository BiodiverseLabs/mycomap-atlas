import { formatNumber } from "@/lib/utils";
import { longDate } from "@/lib/tracker";
import { flowRows, type RecordFlowData } from "@/lib/recordFlow";

// Where mycomap.org's records go before Atlas fits a map: one bar per step,
// shrinking as records leave, with how many left and why. The counts are the
// pull's own (lib/recordFlow.ts); a flow that does not add up is not shown.

function Bar({ share, used }: { share: number; used?: boolean }) {
  return (
    <div className="h-3 w-full rounded-full bg-[#A87146]/10" aria-hidden="true">
      <div
        className={`h-3 rounded-full ${used ? "bg-myco-green" : "bg-myco-green/45"}`}
        style={{ width: `${Math.max(share * 100, 0.6)}%` }}
      />
    </div>
  );
}

const ROW = "grid gap-x-4 gap-y-1 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]";

export default function RecordFlow({ data }: { data: RecordFlowData }) {
  const rows = flowRows(data);
  if (!rows) return null;
  const pulledOn = longDate(data.pulled_at.slice(0, 10));
  const total = data.total;
  return (
    <figure className="rounded-xl border border-[#A87146]/15 bg-[#f8f5f0]/60 p-4 sm:p-6">
      <figcaption className="mb-4">
        <h3 className="font-display text-lg text-[#4a3728]">Where the records go</h3>
        <p className="text-sm">
          Of {formatNumber(total)} records on mycomap.org, {formatNumber(data.used)} train the maps. Each bar is what is
          left after a step; beside it, how many that step leaves out and why. Counted from the pull of {pulledOn}, and
          again every night.
        </p>
      </figcaption>

      {/* The picture; the table after it says the same for screen readers. */}
      <ol className="space-y-3" aria-hidden="true">
        <li className={ROW}>
          <div className="min-w-0">
            <div className="flex items-baseline justify-between gap-2 text-sm">
              <span className="font-medium text-[#4a3728]">
                All records on mycomap.org
              </span>
              <span className="tabular-nums text-[#4a3728]">{formatNumber(total)}</span>
            </div>
            <Bar share={1} />
          </div>
        </li>
        {rows.map((row) => (
          <li key={row.id} className={ROW}>
            <div className="min-w-0">
              <div className="flex items-baseline justify-between gap-2 text-sm">
                <span className="font-medium text-[#4a3728]">
                  {row.label}
                </span>
                <span className="tabular-nums text-[#4a3728]">{formatNumber(row.left)}</span>
              </div>
              <Bar share={row.left / total} />
            </div>
            <div className="text-xs leading-snug sm:pt-0.5">
              <span className="font-semibold tabular-nums text-[#A87146]">−{formatNumber(row.removed)}</span> {row.why}
              {row.parts.length > 0 && (
                <span className="block text-[#5c4a3a]/80">
                  {row.parts.map((p) => `${formatNumber(p.count)} ${p.label}`).join(" · ")}
                </span>
              )}
            </div>
          </li>
        ))}
        <li className={`${ROW} border-t border-[#A87146]/15 pt-3`}>
          <div className="min-w-0">
            <div className="flex items-baseline justify-between gap-2">
              <span className="font-display text-base text-myco-green">Used to build the maps</span>
              <span className="font-display text-base tabular-nums text-myco-green">{formatNumber(data.used)}</span>
            </div>
            <Bar share={data.used / total} used />
          </div>
          <div className="text-xs leading-snug sm:pt-1">
            {Math.round((data.used / total) * 100)}% of mycomap.org&rsquo;s records: every one confirmed by DNA, placed
            precisely, and named to species.
          </div>
        </li>
      </ol>

      <table className="sr-only">
        <caption>Where mycomap.org&rsquo;s records go before Atlas uses them, pull of {pulledOn}</caption>
        <thead>
          <tr>
            <th scope="col">Step</th>
            <th scope="col">Records left</th>
            <th scope="col">Left out</th>
            <th scope="col">Why</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th scope="row">All records on mycomap.org</th>
            <td>{formatNumber(total)}</td>
            <td />
            <td />
          </tr>
          {rows.map((row) => (
            <tr key={row.id}>
              <th scope="row">{row.label}</th>
              <td>{formatNumber(row.left)}</td>
              <td>{formatNumber(row.removed)}</td>
              <td>
                {row.why}
                {row.parts.length > 0 && ` (${row.parts.map((p) => `${formatNumber(p.count)} ${p.label}`).join("; ")})`}
              </td>
            </tr>
          ))}
          <tr>
            <th scope="row">Used to build the maps</th>
            <td>{formatNumber(data.used)}</td>
            <td />
            <td />
          </tr>
        </tbody>
      </table>
    </figure>
  );
}
