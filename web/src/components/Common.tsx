import type { ReactNode } from "react";

import { Card, CardContent } from "@/components/ui/card";

/** A figure with its label, as on Vision's and .org's stat panels. */
export function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: ReactNode }) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="text-xs uppercase tracking-wider text-muted-foreground">{label}</div>
        <div className="mt-1 text-2xl font-semibold text-[#4a3728] tabular-nums">
          {value}
          {hint && <span className="ml-1 text-sm font-normal text-muted-foreground">{hint}</span>}
        </div>
      </CardContent>
    </Card>
  );
}

/** What to do when the development API is not running. */
export function ApiDown() {
  return (
    <Card>
      <CardContent className="p-6">
        <h2 className="text-lg font-semibold text-[#4a3728]">The API is not answering</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Start it from the repository root, then reload:
        </p>
        <pre className="mt-3 rounded-md bg-muted p-3 text-sm">./atlas api</pre>
      </CardContent>
    </Card>
  );
}

/** Table header cell, in Vision's style. */
export function Th({ children, right }: { children: ReactNode; right?: boolean }) {
  return (
    <th className={`${right ? "text-right" : "text-left"} font-medium px-4 py-2`}>{children}</th>
  );
}

/** Blocked AUC, coloured by what it means rather than by how high it is. */
export function Auc({ value }: { value?: number | null }) {
  if (value == null || !Number.isFinite(value)) {
    return <span className="text-muted-foreground">—</span>;
  }
  const tone =
    value >= 0.7 ? "text-myco-green font-semibold" : value < 0.55 ? "text-muted-foreground" : "";
  return <span className={`tabular-nums ${tone}`}>{value.toFixed(2)}</span>;
}

export function Loading() {
  return <p className="text-sm text-muted-foreground">Loading…</p>;
}
