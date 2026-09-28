import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "wouter";
import { CircleMarker, ImageOverlay, MapContainer, TileLayer, Tooltip } from "react-leaflet";
import "leaflet/dist/leaflet.css";

import { getCells, getModel, getTaxon, mapUrl } from "@/lib/api";
import { formatNumber, formatWhen } from "@/lib/utils";

const PUBLISH_AT = 20;

function Legend() {
  return (
    <div className="flex items-center gap-2 text-xs text-muted-foreground">
      <span>Less suitable</span>
      <div
        className="h-2 w-32 rounded"
        style={{ background: "linear-gradient(to right, #f7f7e8, #94c440, #2e5a17)" }}
      />
      <span>More suitable</span>
    </div>
  );
}

function Score({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="rounded-lg border border-border bg-card p-3">
      <div className="text-xs uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className="mt-1 text-xl font-semibold lining-nums">
        {value}
        {hint && (
          <span className="ml-1 text-sm font-normal text-muted-foreground">{hint}</span>
        )}
      </div>
    </div>
  );
}

/** A standard deviation is missing when only one fold could be scored. */
function spread(value: number): string | undefined {
  return Number.isFinite(value) ? `± ${value.toFixed(2)}` : undefined;
}

export default function Taxon() {
  const params = useParams<{ name: string }>();
  const name = decodeURIComponent(params.name ?? "");

  const taxon = useQuery({ queryKey: ["taxon", name], queryFn: () => getTaxon(name) });
  const cells = useQuery({ queryKey: ["cells", name], queryFn: () => getCells(name) });
  const model = useQuery({ queryKey: ["model", name], queryFn: () => getModel(name) });

  const points = cells.data?.cells ?? [];
  const busiest = points.reduce((most, cell) => Math.max(most, cell.records), 1);
  const bounds = model.data?.bounds;
  const overlay: [[number, number], [number, number]] | null = bounds
    ? [
        [bounds.south, bounds.west],
        [bounds.north, bounds.east],
      ]
    : null;
  const centre: [number, number] = points.length
    ? [
        points.reduce((sum, cell) => sum + cell.lat, 0) / points.length,
        points.reduce((sum, cell) => sum + cell.lng, 0) / points.length,
      ]
    : [44, -100];

  return (
    <div className="space-y-6">
      <div>
        <Link href="/taxa" className="text-sm text-muted-foreground hover:text-foreground">
          ← All taxa
        </Link>
        <h1 className="mt-2 font-species text-2xl font-semibold tracking-tight">{name}</h1>
        {taxon.data && (
          <p className="mt-1 text-sm text-muted-foreground lining-nums">
            {formatNumber(taxon.data.records)} validated records ·{" "}
            {formatNumber(taxon.data.localities)} independent localities · fingerprint{" "}
            {taxon.data.fingerprint.slice(0, 12)}
          </p>
        )}
      </div>

      <div className="overflow-hidden rounded-lg border border-border bg-card">
        <div className="h-[520px]">
          <MapContainer
            center={centre}
            zoom={4}
            bounds={overlay ?? undefined}
            className="h-full w-full"
            // Otherwise scrolling the page over the map zooms it instead.
            scrollWheelZoom={false}
          >
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />

            {overlay && <ImageOverlay url={mapUrl(name)} bounds={overlay} opacity={0.8} />}

            {points.map((cell) => (
              <CircleMarker
                key={`${cell.lat}:${cell.lng}`}
                center={[cell.lat, cell.lng]}
                radius={3 + (cell.records / busiest) * 6}
                pathOptions={{
                  color: "#1b2a12",
                  fillColor: "#ffffff",
                  fillOpacity: 0.85,
                  weight: 1,
                }}
              >
                <Tooltip>
                  {formatNumber(cell.records)} record{cell.records === 1 ? "" : "s"}
                </Tooltip>
              </CircleMarker>
            ))}
          </MapContainer>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-2">
          <p className="text-xs text-muted-foreground">
            Collections aggregated to {cells.data?.degrees ?? 0.1}° cells. Exact
            coordinates stay on the machine that pulled them.
          </p>
          {overlay && <Legend />}
        </div>
      </div>

      {model.isLoading && <p className="text-sm text-muted-foreground">Checking for a model…</p>}

      {model.data ? (
        <section className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Score
              label="Blocked AUC"
              value={model.data.auc_mean.toFixed(2)}
              hint={spread(model.data.auc_sd)}
            />
            <Score
              label="Blocked Boyce"
              value={model.data.boyce_mean.toFixed(2)}
              hint={spread(model.data.boyce_sd)}
            />
            <Score label="Presence cells" value={formatNumber(model.data.presences)} />
            <Score label="Background" value={formatNumber(model.data.background)} />
          </div>

          <div className="rounded-lg border border-border bg-card p-4 text-sm text-muted-foreground">
            <p>
              <strong className="text-foreground">Read AUC as a comparison, not a grade.</strong>{" "}
              The background is drawn from every DNA-validated collection of every
              taxon, so this score measures how distinguishable this species is from
              where fungi get collected at all. A species that grows wherever people
              look scores near 0.5, and that is the honest answer rather than a
              failure.
            </p>
            <p className="mt-2 lining-nums">
              Scored on {model.data.folds.length} spatial folds of{" "}
              {formatNumber(model.data.block_km)} km, never a random split.{" "}
              {formatNumber(model.data.predictors.length)} predictors, feature classes{" "}
              <code className="rounded bg-muted px-1">{model.data.classes}</code>, over{" "}
              {formatNumber(model.data.area_km2)} km² of accessible ground. Fitted{" "}
              {formatWhen(model.data.built_at)}.
            </p>
          </div>
        </section>
      ) : (
        !model.isLoading && (
          <section className="rounded-lg border border-dashed border-border p-4 text-sm text-muted-foreground">
            <h2 className="font-semibold text-foreground">Suitability model</h2>
            {taxon.data && taxon.data.localities < PUBLISH_AT ? (
              <p className="mt-1">
                Not enough evidence to model: {formatNumber(taxon.data.localities)}{" "}
                localities, and a map needs {PUBLISH_AT}. This taxon is a survey
                target instead.
              </p>
            ) : (
              <p className="mt-1">
                Not fitted yet. Run{" "}
                <code className="rounded bg-muted px-1">./atlas fit --taxon="{name}"</code>.
              </p>
            )}
          </section>
        )
      )}
    </div>
  );
}
