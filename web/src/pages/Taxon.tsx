import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "wouter";
import { CircleMarker, MapContainer, TileLayer, Tooltip } from "react-leaflet";
import "leaflet/dist/leaflet.css";

import { getCells, getTaxon } from "@/lib/api";
import { formatNumber } from "@/lib/utils";

const PUBLISH_AT = 20;

export default function Taxon() {
  const params = useParams<{ name: string }>();
  const name = decodeURIComponent(params.name ?? "");

  const taxon = useQuery({ queryKey: ["taxon", name], queryFn: () => getTaxon(name) });
  const cells = useQuery({ queryKey: ["cells", name], queryFn: () => getCells(name) });

  const points = cells.data?.cells ?? [];
  const busiest = points.reduce((most, cell) => Math.max(most, cell.records), 1);
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
            {formatNumber(taxon.data.localities)} independent localities ·
            fingerprint {taxon.data.fingerprint.slice(0, 12)}
          </p>
        )}
      </div>

      <div className="overflow-hidden rounded-lg border border-border bg-card">
        <div className="h-[480px]">
          <MapContainer center={centre} zoom={4} className="h-full w-full" scrollWheelZoom>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            {points.map((cell) => (
              <CircleMarker
                key={`${cell.lat}:${cell.lng}`}
                center={[cell.lat, cell.lng]}
                radius={4 + (cell.records / busiest) * 8}
                pathOptions={{
                  color: "hsl(82 53% 35%)",
                  fillColor: "hsl(82 53% 51%)",
                  fillOpacity: 0.7,
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
        <p className="border-t border-border px-4 py-2 text-xs text-muted-foreground">
          Collections aggregated to {cells.data?.degrees ?? 0.1}° cells. Exact
          coordinates stay on the machine that pulled them.
        </p>
      </div>

      <section className="rounded-lg border border-dashed border-border p-4 text-sm text-muted-foreground">
        <h2 className="font-semibold text-foreground">Suitability model</h2>
        {taxon.data && taxon.data.localities < PUBLISH_AT ? (
          <p className="mt-1">
            Not enough evidence to model: {formatNumber(taxon.data.localities)}{" "}
            localities, and phase 1 needs {PUBLISH_AT}. This taxon is a survey
            target instead.
          </p>
        ) : (
          <p className="mt-1">
            Not fitted yet. Environmental layers and the target-group background
            are the next stage; this panel will hold the suitability map,
            uncertainty and evaluation scores.
          </p>
        )}
      </section>
    </div>
  );
}
