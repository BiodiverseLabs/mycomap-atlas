import { useQueries, useQuery } from "@tanstack/react-query";
import { useParams, useSearch } from "wouter";
import { ArrowUpRight } from "lucide-react";

import { CircleMarker, FitBounds, ImageOverlay, MapContainer, TileLayer } from "@/components/Leaflet";
import { defaultStrength } from "@/components/MapStrength";
import {
  ALGORITHMS,
  ALGORITHM_LABELS,
  FULL_MODELS,
  getCells,
  getModel,
  getTaxon,
  mapUrl,
  type Algorithm,
  type Model,
} from "@/lib/api";
import { sparseFailedNote } from "@/lib/sparseSkill";
import { formatNumber } from "@/lib/utils";

/**
 * The map to show: the one asked for if it was fitted, else the small-model
 * ensemble for a sparse taxon, else the first of the full models that exists.
 */
function pickAlgorithm(requested: string | null, models: Partial<Record<Algorithm, Model | null>>) {
  if (requested && (ALGORITHMS as readonly string[]).includes(requested) && models[requested as Algorithm]) {
    return requested as Algorithm;
  }
  if (models.esm) return "esm";
  return FULL_MODELS.find((a) => models[a]) ?? null;
}

/**
 * One taxon's map with nothing around it, for another site's iframe:
 * /embed/taxa/<name>?model=maxnet&points=0. The site's header and footer are
 * left out; a strip along the bottom names the taxon and links back here.
 */
export default function Embed() {
  const params = useParams<{ name: string }>();
  const name = decodeURIComponent(params.name ?? "");
  const search = new URLSearchParams(useSearch());
  const showPoints = search.get("points") !== "0";

  const taxon = useQuery({ queryKey: ["taxon", name], queryFn: () => getTaxon(name) });
  const cells = useQuery({ queryKey: ["cells", name], queryFn: () => getCells(name), enabled: showPoints });
  const fits = useQueries({
    queries: ALGORITHMS.map((algorithm) => ({
      queryKey: ["model", name, algorithm],
      queryFn: () => getModel(name, algorithm),
    })),
  });
  const models: Partial<Record<Algorithm, Model | null>> = {};
  ALGORITHMS.forEach((a, i) => {
    models[a] = fits[i].data;
  });
  const loading = fits.some((f) => f.isLoading);
  const algorithm = pickAlgorithm(search.get("model"), models);
  const model = algorithm ? models[algorithm] : null;
  const failed = model?.skill === "failed";
  const bounds = model?.bounds
    ? ([[model.bounds.south, model.bounds.west], [model.bounds.north, model.bounds.east]] as [
        [number, number],
        [number, number],
      ])
    : null;
  const points = showPoints ? cells.data?.cells ?? [] : [];
  const busiest = points.reduce((most, cell) => Math.max(most, cell.records), 1);
  const page = `/taxa/${encodeURIComponent(name)}`;

  let note: string | null = null;
  if (!loading && !model) note = "No habitat map for this taxon yet.";
  else if (model?.map_withheld) note = "This map is drawn at the taxon's next fit.";
  else if (failed) {
    note =
      algorithm === "esm"
        ? sparseFailedNote(model?.presences ?? 0)
        : "No better than its null models: this map says little about habitat.";
  }

  return (
    <div className="flex h-screen flex-col bg-white text-[#4a3728]">
      <div className="relative flex-1">
        <MapContainer center={[44, -100]} zoom={3} className="h-full w-full" scrollWheelZoom={false}>
          <FitBounds bounds={bounds} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a>'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          {bounds && algorithm && !model?.map_withheld && (
            <ImageOverlay
              url={mapUrl(name, algorithm, model?.map_drawn_at ?? model?.built_at)}
              bounds={bounds}
              opacity={defaultStrength(failed) / 100}
            />
          )}
          {points.map((cell) => (
            <CircleMarker
              key={`${cell.lat}:${cell.lng}`}
              center={[cell.lat, cell.lng]}
              radius={2 + (cell.records / busiest) * 5}
              pathOptions={{ color: "#4a3728", fillColor: "#ffffff", fillOpacity: 0.85, weight: 1 }}
              tooltip={`${formatNumber(cell.records)} record${cell.records === 1 ? "" : "s"}`}
            />
          ))}
        </MapContainer>
        {note && (
          <div className="pointer-events-none absolute inset-x-0 bottom-3 z-[500] mx-auto max-w-[90%] w-fit rounded-md bg-white/90 px-3 py-1 text-center text-xs text-muted-foreground shadow">
            {note}
          </div>
        )}
      </div>
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-[#A87146]/20 bg-[#f8f5f0] px-3 py-1.5 text-xs">
        <a href={page} target="_blank" rel="noopener" className="inline-flex items-center gap-1 hover:text-myco-green">
          <span className="sci font-medium">{name}</span>
          {taxon.data && (
            <span className="text-muted-foreground tabular-nums">
              · {formatNumber(taxon.data.records)} DNA-validated records
            </span>
          )}
          {algorithm && <span className="text-muted-foreground">· {ALGORITHM_LABELS[algorithm]}</span>}
        </a>
        <span className="flex items-center gap-3">
          {model && (
            <span className="hidden items-center gap-1.5 text-muted-foreground sm:flex">
              Less suitable
              <span
                className="h-2 w-16 rounded"
                style={{ background: "linear-gradient(to right, #f7f7e8, #94c440, #2e5a17)" }}
              />
              More
            </span>
          )}
          <a
            href={page}
            target="_blank"
            rel="noopener"
            className="inline-flex items-center gap-0.5 font-semibold text-myco-brown hover:text-myco-green"
          >
            MycoMap <span className="text-myco-green">Atlas</span>
            <ArrowUpRight className="h-3 w-3" />
          </a>
        </span>
      </div>
    </div>
  );
}
