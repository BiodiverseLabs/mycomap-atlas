import { useState } from "react";
import { ChevronRight } from "lucide-react";

import { Help } from "@/components/Common";
import { Card, CardContent } from "@/components/ui/card";
import { ALGORITHMS, ALGORITHM_LABELS, type Algorithm, type Model, type ModelImportance } from "@/lib/api";

// Below this fall in held-out AUC, shuffling a variable made no measurable
// difference: the models are scored on a few hundred sites, and noise alone
// moves AUC by about this much.
const NO_EFFECT = 0.002;

/** Which model to open on: the forest if it has a breakdown, it being the
 * most skilled of the three on most taxa, else the first that has one. */
function firstWithBreakdown(models: Partial<Record<Algorithm, Model | null>>): Algorithm | undefined {
  const order: Algorithm[] = ["rf", "maxnet", "xgboost"];
  return order.find((a) => models[a]?.importance?.length);
}

function Bar({ value, max }: { value: number; max: number }) {
  const width = max > 0 ? Math.max(0, Math.min(1, value / max)) * 100 : 0;
  const faint = value < NO_EFFECT;
  return (
    <div className="h-2 w-full rounded-full bg-[#A87146]/10" aria-hidden="true">
      <div
        className={`h-2 rounded-full ${faint ? "bg-[#A87146]/25" : "bg-myco-green"}`}
        style={{ width: `${width}%` }}
      />
    </div>
  );
}

function fall(value?: number) {
  if (value == null || !Number.isFinite(value)) return "—";
  if (value < NO_EFFECT) return "no measurable effect";
  return value.toFixed(3);
}

function Layer({ layer, max }: { layer: ModelImportance; max: number }) {
  const [open, setOpen] = useState(false);
  const predictors = layer.predictors ?? [];
  return (
    <li className="border-b border-[#A87146]/10 last:border-0">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className="grid w-full grid-cols-[1.25rem_minmax(7rem,11rem)_1fr_auto] items-center gap-3 py-2 text-left text-sm hover:bg-[#A87146]/5"
      >
        <ChevronRight
          className={`h-4 w-4 text-[#A87146] transition-transform ${open ? "rotate-90" : ""}`}
          aria-hidden="true"
        />
        <span className="font-medium text-[#4a3728]">{layer.label}</span>
        <Bar value={layer.fall ?? 0} max={max} />
        <span className="w-36 text-right tabular-nums text-xs text-[#5c4a3a]">{fall(layer.fall)}</span>
      </button>
      {open && (
        <ul className="mb-2 ml-8">
          {predictors.map((p) => (
            <li
              key={p.name}
              className="grid grid-cols-[minmax(7rem,14rem)_1fr_auto] items-center gap-3 py-1 text-xs text-[#5c4a3a]"
            >
              <span title={p.name}>{p.label}</span>
              <Bar value={p.fall ?? 0} max={max} />
              <span className="w-36 text-right tabular-nums">{fall(p.fall)}</span>
            </li>
          ))}
          {predictors.length > 1 && (
            <li className="pt-1 text-[11px] text-muted-foreground">
              Variables inside one dataset overlap, so each alone can matter less than the dataset
              together: when one is scrambled, its near-twins still carry the information.
            </li>
          )}
        </ul>
      )}
    </li>
  );
}

/** What each map rests on: how much it relies on each dataset and each
 * variable, measured on ground the model never saw. */
export function WhatDrives({ models }: { models: Partial<Record<Algorithm, Model | null>> }) {
  const available = ALGORITHMS.filter((a) => models[a]?.importance?.length);
  const [chosen, setChosen] = useState<Algorithm | undefined>(undefined);
  const algorithm = chosen && available.includes(chosen) ? chosen : firstWithBreakdown(models);
  if (!algorithm) {
    return (
      <p className="text-sm text-muted-foreground">
        These maps were fitted before Atlas measured what each map rests on; the next refit adds it.
      </p>
    );
  }
  const model = models[algorithm]!;
  const layers = model.importance ?? [];
  const max = Math.max(
    NO_EFFECT,
    ...layers.map((l) => l.fall ?? 0),
    ...layers.flatMap((l) => (l.predictors ?? []).map((p) => p.fall ?? 0)),
  );
  const used = new Set(layers.map((l) => l.name));
  const unused = (model.layers_unused ?? []).filter((id) => !used.has(id));

  return (
    <Card>
      <CardContent className="p-4">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <div className="inline-flex rounded-md border border-[#A87146]/20 p-0.5 text-xs" role="group" aria-label="Which model">
            {available.map((a) => (
              <button
                key={a}
                type="button"
                onClick={() => setChosen(a)}
                aria-pressed={a === algorithm}
                className={`rounded px-2 py-1 ${
                  a === algorithm ? "bg-myco-green text-white" : "text-[#5c4a3a] hover:bg-[#A87146]/10"
                }`}
              >
                {ALGORITHM_LABELS[a]}
              </button>
            ))}
          </div>
          <span className="flex items-center gap-1 text-xs text-muted-foreground">
            Fall in held-out AUC when scrambled
            <Help label="How this is measured">
              <p>
                For each spatial fold, the model is scored on the region it never saw, then scored
                again with one dataset's values (or one variable's) shuffled among those sites. The
                drop in blocked AUC is how much the map relied on it there; the bar is the average
                over the folds.
              </p>
              <p className="mt-1.5">
                Measured on unseen ground, a variable the model only memorised shows no drop at all.
                A dataset's drop is usually more than any one of its variables', because related
                variables stand in for one another when only one is scrambled.
              </p>
            </Help>
          </span>
        </div>
        <ul>
          {layers.map((layer) => (
            <Layer key={layer.name} layer={layer} max={max} />
          ))}
        </ul>
        {unused.length > 0 && (
          <p className="mt-2 text-xs text-muted-foreground">
            Not used by this model: {unused.join(", ")}. Maxent keeps one of each group of
            closely related variables and about one variable for every four sites.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
