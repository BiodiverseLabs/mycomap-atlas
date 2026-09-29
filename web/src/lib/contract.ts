// The OpenAPI description and the list of sources, read at build time from
// inst/api — the same files the API serves at /api/openapi.json and
// /api/sources. R tests hold both to the code (tests/testthat/test-openapi.R
// and test-sources.R), so these pages cannot drift from what Atlas does.

import openapiJson from "@contract/openapi.json";
import sourcesJson from "@contract/sources.json";

export interface Dataset {
  id: string;
  name: string;
  provider?: string;
  url: string;
  license: string;
  license_url?: string;
  role: string;
  citation?: string;
  doi?: string;
}

export interface Software {
  name: string;
  group: "platform" | "r" | "web";
  version?: string;
  license: string;
  url: string;
  role: string;
  citation?: string;
  doi?: string;
}

export interface Reference {
  citation: string;
  doi?: string;
  used_for: string;
}

export type Availability = "published" | "in releases" | "planned" | "at source" | "withheld";

export interface Product {
  stage: string;
  name: string;
  detail: string;
  availability: Availability;
  where?: string;
  why?: string;
}

export interface Sources {
  about: string;
  datasets: Dataset[];
  software: Software[];
  references: Reference[];
  products: Product[];
}

export const SOURCES = sourcesJson as Sources;

// Just enough of OpenAPI 3.1 to draw the reference.
export interface Schema {
  $ref?: string;
  type?: string | string[];
  format?: string;
  description?: string;
  enum?: string[];
  default?: unknown;
  minimum?: number;
  required?: string[];
  properties?: Record<string, Schema>;
  items?: Schema;
  additionalProperties?: Schema | boolean;
}

export interface Parameter {
  $ref?: string;
  name: string;
  in: "path" | "query";
  required?: boolean;
  description?: string;
  schema?: Schema;
  example?: unknown;
}

export interface MediaType {
  schema?: Schema;
  example?: unknown;
}

export interface ApiResponse {
  $ref?: string;
  description: string;
  content?: Record<string, MediaType>;
}

export interface Operation {
  tags?: string[];
  operationId: string;
  summary: string;
  description?: string;
  parameters?: Parameter[];
  responses: Record<string, ApiResponse>;
}

export interface OpenApi {
  info: { title: string; version: string; summary?: string; description?: string };
  servers: { url: string; description?: string }[];
  tags: { name: string; description?: string }[];
  paths: Record<string, { get: Operation }>;
  components: {
    parameters: Record<string, Parameter>;
    responses: Record<string, ApiResponse>;
    schemas: Record<string, Schema>;
  };
}

export const OPENAPI = openapiJson as unknown as OpenApi;

/** Follow a "#/components/..." reference, or return the node as it is. */
export function resolve<T extends { $ref?: string }>(node: T): T {
  if (!node.$ref) return node;
  const parts = node.$ref.replace(/^#\//, "").split("/");
  let target: unknown = OPENAPI;
  for (const part of parts) target = (target as Record<string, unknown>)[part];
  return target as T;
}

/** The name a schema reference points at, e.g. "Taxon". */
export function refName(ref?: string): string | undefined {
  return ref?.split("/").pop();
}

export const GITHUB_URL = "https://github.com/BiodiverseLabs/mycomap-atlas";
