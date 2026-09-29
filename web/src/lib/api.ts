// The development API is the plumber server started by `./atlas api`. In
// production the same routes are served from atlas.mycomap.org.

export interface Status {
  ready: boolean;
  pulledAt?: string;
  records?: number;
  taxa?: number;
  fingerprint?: string;
  since?: string | null;
}

export interface Taxon {
  scientific_name: string;
  records: number;
  localities: number;
  fingerprint: string;
}

export interface TaxaPage {
  total: number;
  items: Taxon[];
}

export interface Cell {
  lat: number;
  lng: number;
  records: number;
}

export interface Cells {
  name: string;
  degrees: number;
  cells: Cell[];
}

export interface Layer {
  id: string;
  title: string;
  source: string;
  license: string;
  citation: string;
  note?: string;
  built: boolean;
  bands?: string[];
  cellSizeM?: number;
  sizeMb?: number;
  builtAt?: string;
}

export interface LayersResponse {
  grid: string;
  layers: Layer[];
}

export interface ModelFold {
  fold: number;
  presences: number;
  auc: number | null;
  boyce: number | null;
}

export interface ModelBounds {
  south: number;
  west: number;
  north: number;
  east: number;
}

export interface Model {
  taxon: string;
  grid: string;
  presences: number;
  background: number;
  area_km2: number;
  predictors: string[];
  classes: string;
  block_km: number;
  folds: ModelFold[];
  auc_mean: number;
  auc_sd: number;
  boyce_mean: number;
  boyce_sd: number;
  built_at: string;
  map?: string;
  bounds?: ModelBounds;
}

/** One row of /api/models: enough for a list. The full record is getModel. */
export interface ModelSummary {
  taxon: string;
  presences?: number;
  predictors: number;
  auc_mean?: number;
  boyce_mean?: number;
  map: boolean;
  built_at: string;
}

async function get<T>(path: string): Promise<T> {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}`);
  }
  return (await response.json()) as T;
}

export function getStatus(): Promise<Status> {
  return get<Status>("/api/status");
}

export function getTaxa(params: {
  search?: string;
  minLocalities?: number;
  limit?: number;
  offset?: number;
}): Promise<TaxaPage> {
  const query = new URLSearchParams({
    search: params.search ?? "",
    min_localities: String(params.minLocalities ?? 0),
    limit: String(params.limit ?? 50),
    offset: String(params.offset ?? 0),
  });
  return get<TaxaPage>(`/api/taxa?${query.toString()}`);
}

/** How many taxa have at least this many independent localities. */
export async function getTaxaCount(minLocalities: number): Promise<number> {
  const page = await getTaxa({ minLocalities, limit: 1 });
  return page.total;
}

export function getLayers(grid = "draft"): Promise<LayersResponse> {
  return get<LayersResponse>(`/api/layers?grid=${encodeURIComponent(grid)}`);
}

export function getTaxon(name: string): Promise<Taxon> {
  return get<Taxon>(`/api/taxa/${encodeURIComponent(name)}`);
}

export function getCells(name: string): Promise<Cells> {
  return get<Cells>(`/api/taxa/${encodeURIComponent(name)}/cells`);
}

/** The fitted model for a taxon, or null when it has not been fitted. */
export async function getModel(name: string): Promise<Model | null> {
  const response = await fetch(`/api/taxa/${encodeURIComponent(name)}/model`);
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return (await response.json()) as Model;
}

export function mapUrl(name: string): string {
  return `/api/taxa/${encodeURIComponent(name)}/map.png`;
}

/** Every fitted model, newest first, as a summary. */
export async function getModels(): Promise<ModelSummary[]> {
  const response = await get<{ models: ModelSummary[] }>("/api/models");
  return response.models;
}
