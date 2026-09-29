import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "wouter";
import { CircleMarker, ImageOverlay, MapContainer, TileLayer, Tooltip } from "react-leaflet";
import { ArrowUpRight } from "lucide-react";
import "leaflet/dist/leaflet.css";

import { Stat } from "@/components/Common";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Card, CardContent } from "@/components/ui/card";
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
    <>
      <PageHeader title={<span className="sci">{name}</span>}>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
          <Link href="/taxa" className="hover:text-myco-green">
            ← All taxa
          </Link>
          {taxon.data && (
            <span className="tabular-nums">
              {formatNumber(taxon.data.records)} validated records ·{" "}
              {formatNumber(taxon.data.localities)} independent localities
            </span>
          )}
          <a
            href={`https://mycomap.org/species/${encodeURIComponent(name)}`}
            className="inline-flex items-center gap-1 hover:text-myco-green"
          >
            On mycomap.org <ArrowUpRight className="h-3.5 w-3.5" />
          </a>
        </div>
      </PageHeader>

      <Page>
        <Card className="overflow-hidden">
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
                    color: "#4a3728",
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

          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#A87146]/10 bg-[#f8f5f0] px-4 py-2">
            <p className="text-xs text-muted-foreground">
              White dots are collections, grouped into {cells.data?.degrees ?? 0.1}° cells. The
              colour stops 500 km from the nearest record: beyond that the model makes no claim
              either way.
            </p>
            {overlay && <Legend />}
          </div>
        </Card>

        {model.isLoading && <p className="text-sm text-muted-foreground">Checking for a model…</p>}

        {model.data ? (
          <section>
            <SectionTitle>How good is this map?</SectionTitle>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Stat
                label="Blocked AUC"
                value={model.data.auc_mean.toFixed(2)}
                hint={spread(model.data.auc_sd)}
              />
              <Stat
                label="Blocked Boyce"
                value={model.data.boyce_mean.toFixed(2)}
                hint={spread(model.data.boyce_sd)}
              />
              <Stat label="Presence cells" value={formatNumber(model.data.presences)} />
              <Stat label="Background" value={formatNumber(model.data.background)} />
            </div>

            <Card className="mt-4">
              <CardContent className="p-5 text-sm text-[#5c4a3a] leading-relaxed space-y-2">
                <p>
                  <strong className="text-[#4a3728]">Read AUC as a comparison, not a grade.</strong>{" "}
                  The background is drawn from every DNA-validated collection of every taxon, so
                  this score measures how distinguishable this species is from where fungi get
                  collected at all. A species that grows wherever people look scores near 0.5,
                  and that is the honest answer rather than a failure.
                </p>
                <p className="tabular-nums">
                  Scored on {model.data.folds.length} spatial folds of{" "}
                  {formatNumber(model.data.block_km)} km, never a random split.{" "}
                  {formatNumber(model.data.predictors.length)} predictors, feature classes{" "}
                  <code className="rounded bg-muted px-1">{model.data.classes}</code>, over{" "}
                  {formatNumber(model.data.area_km2)} km² of accessible ground. Fitted{" "}
                  {formatWhen(model.data.built_at)}.
                </p>
              </CardContent>
            </Card>
          </section>
        ) : (
          !model.isLoading && (
            <Card className="border-dashed">
              <CardContent className="p-5 text-sm text-[#5c4a3a]">
                <h2 className="font-semibold text-[#4a3728]">No habitat map yet</h2>
                {taxon.data && taxon.data.localities < PUBLISH_AT ? (
                  <p className="mt-1">
                    {formatNumber(taxon.data.localities)} independent localities so far, and a map
                    needs about {PUBLISH_AT}. This taxon is a survey target: every new sequenced
                    collection from a new place brings a map closer.
                  </p>
                ) : (
                  <p className="mt-1">
                    Enough records to model, but it has not been fitted yet. Run{" "}
                    <code className="rounded bg-muted px-1">./atlas fit --taxon="{name}"</code>.
                  </p>
                )}
              </CardContent>
            </Card>
          )
        )}
      </Page>
    </>
  );
}
