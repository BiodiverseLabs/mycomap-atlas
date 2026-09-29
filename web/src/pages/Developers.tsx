import { useState, type ReactNode } from "react";
import { ArrowUpRight, Braces, FileJson, KeyRound, Play, Scale, Server } from "lucide-react";

import { GithubMark } from "@/components/Common";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  GITHUB_URL,
  OPENAPI,
  refName,
  resolve,
  type Operation,
  type Parameter,
  type Schema,
} from "@/lib/contract";

const PUBLIC_BASE = OPENAPI.servers[0]?.url ?? "https://atlas.mycomap.org";
const RATES = OPENAPI["x-rate-limits"];
const TOKEN_REQUEST_URL = "https://mycomap.org/atlas-tokens";

interface Endpoint {
  path: string;
  op: Operation;
  params: Parameter[];
}

const ENDPOINTS: Endpoint[] = Object.entries(OPENAPI.paths).map(([path, item]) => ({
  path,
  op: item.get,
  params: (item.get.parameters ?? []).map((p) => resolve(p)),
}));

const anchor = (e: Endpoint) => e.op.operationId;

function typeLabel(schema?: Schema): string {
  if (!schema) return "";
  if (schema.$ref) return refName(schema.$ref) ?? "object";
  if (schema.enum) return schema.enum.join(" | ");
  if (schema.type === "array") return `${typeLabel(schema.items)}[]`;
  const type = Array.isArray(schema.type) ? schema.type.join(" | ") : schema.type ?? "any";
  return schema.format && schema.format !== "binary" ? `${type} (${schema.format})` : type;
}

/** Example values for a request: the spec's examples, else defaults. */
function initialValues(params: Parameter[]): Record<string, string> {
  const values: Record<string, string> = {};
  for (const p of params) {
    const example = p.example ?? (p.in === "path" ? "" : undefined);
    if (example !== undefined) values[p.name] = String(example);
  }
  return values;
}

function buildUrl(path: string, params: Parameter[], values: Record<string, string>, base = ""): string {
  let url = path;
  const query = new URLSearchParams();
  for (const p of params) {
    const value = values[p.name];
    if (p.in === "path") url = url.replace(`{${p.name}}`, encodeURIComponent(value ?? ""));
    else if (value) query.set(p.name, value);
  }
  const qs = query.toString();
  return `${base}${url}${qs ? `?${qs}` : ""}`;
}

function Code({ children }: { children: ReactNode }) {
  return (
    <pre className="overflow-x-auto rounded-md bg-[#2b211a] p-3 text-[13px] leading-relaxed text-[#f3ece3]">
      <code>{children}</code>
    </pre>
  );
}

const QUICKSTART: { id: string; label: string; code: string }[] = [
  {
    id: "curl",
    label: "curl",
    code: `curl "${PUBLIC_BASE}/api/taxa?search=Mycena&min_localities=20&limit=5"

curl "${PUBLIC_BASE}/api/taxa/Trametes%20versicolor/model?algorithm=rf"`,
  },
  {
    id: "r",
    label: "R",
    code: `library(jsonlite)
base <- "${PUBLIC_BASE}/api"

taxa  <- fromJSON(paste0(base, "/taxa?min_localities=20&limit=500"))$items
model <- fromJSON(paste0(base, "/taxa/", URLencode("Trametes versicolor"), "/model?algorithm=rf"))
model$auc_mean`,
  },
  {
    id: "python",
    label: "Python",
    code: `import requests
from urllib.parse import quote

base = "${PUBLIC_BASE}/api"
taxa = requests.get(f"{base}/taxa", params={"min_localities": 20, "limit": 500}).json()["items"]
model = requests.get(f"{base}/taxa/{quote('Trametes versicolor')}/model",
                     params={"algorithm": "rf"}).json()
print(model["auc_mean"], model["predictors"])`,
  },
  {
    id: "js",
    label: "JavaScript",
    code: `const base = "${PUBLIC_BASE}/api";
const name = encodeURIComponent("Trametes versicolor");

const model = await fetch(\`\${base}/taxa/\${name}/model?algorithm=rf\`).then((r) => r.json());
// Lay the map over Leaflet at the model's bounds:
const { south, west, north, east } = model.bounds;
L.imageOverlay(\`\${base}/taxa/\${name}/map.png?algorithm=rf\`, [[south, west], [north, east]]).addTo(map);`,
  },
];

function QuickStart() {
  const [tab, setTab] = useState("curl");
  const current = QUICKSTART.find((q) => q.id === tab) ?? QUICKSTART[0];
  return (
    <Card>
      <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-2 px-4">
        <div className="flex flex-wrap gap-1" role="tablist">
          {QUICKSTART.map((q) => (
            <button
              key={q.id}
              role="tab"
              aria-selected={q.id === tab}
              onClick={() => setTab(q.id)}
              className={`rounded-md px-3 py-1 text-sm font-medium ${
                q.id === tab ? "bg-myco-green/15 text-[#2e5a17]" : "text-gray-600 hover:bg-myco-green/5"
              }`}
            >
              {q.label}
            </button>
          ))}
        </div>
      </CardHeader>
      <CardContent className="p-3">
        <Code>{current.code}</Code>
      </CardContent>
    </Card>
  );
}

function Fact({ icon: Icon, label, children }: { icon: typeof Server; label: string; children: ReactNode }) {
  return (
    <div className="flex gap-3">
      <Icon className="mt-0.5 h-5 w-5 shrink-0 text-myco-green" />
      <div>
        <div className="text-sm font-semibold text-[#4a3728]">{label}</div>
        <div className="text-sm text-[#5c4a3a] leading-relaxed">{children}</div>
      </div>
    </div>
  );
}

/** The fields of a response body, one level deep, with nested types named. */
function Fields({ schema }: { schema?: Schema }) {
  const resolved = schema ? resolve(schema) : undefined;
  const target = resolved?.type === "array" && resolved.items ? resolve(resolved.items) : resolved;
  const properties = target?.properties;
  if (!properties) {
    return target?.description ? <p className="text-sm text-muted-foreground">{target.description}</p> : null;
  }
  const required = new Set(target?.required ?? []);
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <tbody>
          {Object.entries(properties).map(([name, field]) => (
            <tr key={name} className="border-b last:border-0 align-top">
              <td className="py-1.5 pr-3 font-mono text-[13px] text-[#4a3728] whitespace-nowrap">
                {name}
                {required.has(name) && <span className="text-destructive">*</span>}
              </td>
              <td className="py-1.5 pr-3 font-mono text-xs text-muted-foreground whitespace-nowrap">
                {typeLabel(field)}
              </td>
              <td className="py-1.5 text-[#5c4a3a]">{resolve(field).description ?? ""}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

interface TryResult {
  status: number;
  ms: number;
  tier?: string | null;
  remaining?: string | null;
  body?: string;
  image?: string;
}

function TryIt({ endpoint, token }: { endpoint: Endpoint; token: string }) {
  const [values, setValues] = useState(() => initialValues(endpoint.params));
  const [result, setResult] = useState<TryResult | null>(null);
  const [busy, setBusy] = useState(false);
  const url = buildUrl(endpoint.path, endpoint.params, values);

  const send = async () => {
    setBusy(true);
    const started = performance.now();
    try {
      const response = await fetch(url, token ? { headers: { "X-API-Key": token } } : undefined);
      const ms = Math.round(performance.now() - started);
      const tier = response.headers.get("X-Atlas-Tier");
      const remaining = response.headers.get("X-RateLimit-Remaining");
      const type = response.headers.get("content-type") ?? "";
      if (type.startsWith("image/") && response.ok) {
        setResult({ status: response.status, ms, tier, remaining, image: URL.createObjectURL(await response.blob()) });
      } else {
        const text = await response.text();
        let body = text;
        try {
          body = JSON.stringify(JSON.parse(text), null, 2);
        } catch {
          /* not JSON: show it as it came */
        }
        const limit = 6000;
        setResult({
          status: response.status,
          ms,
          tier,
          remaining,
          body: body.length > limit ? `${body.slice(0, limit)}\n… ${body.length - limit} more characters` : body || "(empty)",
        });
      }
    } catch (error) {
      setResult({ status: 0, ms: 0, body: `The API did not answer: ${String(error)}` });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-3">
      {endpoint.params.length > 0 && (
        <div className="grid gap-2 sm:grid-cols-2">
          {endpoint.params.map((p) => (
            <label key={p.name} className="text-xs text-muted-foreground">
              <span className="font-mono">{p.name}</span>
              {p.schema?.enum ? (
                <select
                  value={values[p.name] ?? ""}
                  onChange={(event) => setValues({ ...values, [p.name]: event.target.value })}
                  className="mt-1 h-9 w-full rounded-md border border-input bg-white px-2 text-sm text-foreground"
                >
                  <option value="">default ({String(p.schema.default ?? "")})</option>
                  {p.schema.enum.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  value={values[p.name] ?? ""}
                  placeholder={p.schema?.default != null ? `default ${String(p.schema.default)}` : ""}
                  onChange={(event) => setValues({ ...values, [p.name]: event.target.value })}
                  className="mt-1 h-9 w-full rounded-md border border-input bg-white px-2 text-sm text-foreground"
                />
              )}
            </label>
          ))}
        </div>
      )}
      <div className="flex flex-wrap items-center gap-3">
        <Button size="sm" onClick={send} disabled={busy}>
          <Play className="mr-1 h-3.5 w-3.5" /> {busy ? "Sending…" : "Send request"}
        </Button>
        <code className="break-all text-xs text-muted-foreground">GET {url}</code>
      </div>
      {result && (
        <div className="space-y-2">
          <div className="text-xs text-muted-foreground">
            {result.status ? (
              <>
                <Badge variant={result.status < 400 ? "default" : "destructive"}>{result.status}</Badge>{" "}
                in {result.ms} ms
                {result.tier && (
                  <>
                    {" · "}
                    {result.tier}, {result.remaining} left this minute
                  </>
                )}
              </>
            ) : null}
          </div>
          {result.image ? (
            <img src={result.image} alt="Map returned by the API" className="max-h-80 rounded border bg-[#f8f5f0]" />
          ) : (
            <Code>{result.body}</Code>
          )}
        </div>
      )}
    </div>
  );
}

function EndpointCard({ endpoint, token }: { endpoint: Endpoint; token: string }) {
  const { op, path, params } = endpoint;
  const example = buildUrl(path, params, initialValues(params), PUBLIC_BASE);
  return (
    <Card id={anchor(endpoint)} className="scroll-mt-24">
      <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 px-4 py-3">
        <div className="flex flex-wrap items-center gap-2">
          <span className="rounded bg-myco-green/15 px-2 py-0.5 font-mono text-xs font-bold text-[#2e5a17]">GET</span>
          <code className="font-mono text-sm text-[#4a3728] break-all">{path}</code>
        </div>
        <CardTitle className="mt-1 text-base text-[#4a3728]">{op.summary}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-5 p-4">
        {op.description && <p className="text-sm text-[#5c4a3a] leading-relaxed">{op.description}</p>}

        {params.length > 0 && (
          <div>
            <h4 className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">Parameters</h4>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <tbody>
                  {params.map((p) => (
                    <tr key={p.name} className="border-b last:border-0 align-top">
                      <td className="py-1.5 pr-3 font-mono text-[13px] text-[#4a3728] whitespace-nowrap">
                        {p.name}
                        {p.required && <span className="text-destructive">*</span>}
                      </td>
                      <td className="py-1.5 pr-3 text-xs text-muted-foreground whitespace-nowrap">
                        {p.in} · <span className="font-mono">{typeLabel(p.schema)}</span>
                        {p.schema?.default !== undefined && p.schema.default !== "" && (
                          <> · default <span className="font-mono">{String(p.schema.default)}</span></>
                        )}
                      </td>
                      <td className="py-1.5 text-[#5c4a3a]">{p.description}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        <div>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">Responses</h4>
          <div className="space-y-3">
            {Object.entries(op.responses).map(([status, raw]) => {
              const response = resolve(raw);
              const [mediaType, media] = Object.entries(response.content ?? {})[0] ?? [];
              return (
                <div key={status}>
                  <div className="flex flex-wrap items-center gap-2 text-sm">
                    <Badge variant={Number(status) < 400 ? "default" : "outline"}>{status}</Badge>
                    <span className="text-[#5c4a3a]">{response.description}</span>
                    {mediaType && <span className="font-mono text-xs text-muted-foreground">{mediaType}</span>}
                    {media?.schema?.$ref && (
                      <span className="font-mono text-xs text-muted-foreground">{refName(media.schema.$ref)}</span>
                    )}
                  </div>
                  {Number(status) < 300 && media?.schema && mediaType === "application/json" && (
                    <div className="mt-2 rounded-md border border-[#A87146]/10 px-3 py-1">
                      <Fields schema={media.schema} />
                    </div>
                  )}
                  {media?.example !== undefined && (
                    <div className="mt-2">
                      <Code>{JSON.stringify(media.example, null, 2)}</Code>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        <div>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">Example</h4>
          <Code>curl "{example}"</Code>
        </div>

        <details className="rounded-md border border-[#A87146]/15 p-3">
          <summary className="cursor-pointer text-sm font-medium text-[#4a3728]">Try it against this server</summary>
          <div className="mt-3">
            <TryIt endpoint={endpoint} token={token} />
          </div>
        </details>
      </CardContent>
    </Card>
  );
}

export default function Developers() {
  // Held only in this page's memory, for Try it; never stored.
  const [token, setToken] = useState("");
  const byTag = OPENAPI.tags.map((tag) => ({
    ...tag,
    endpoints: ENDPOINTS.filter((e) => e.op.tags?.[0] === tag.name),
  }));

  return (
    <>
      <PageHeader title="Developers">
        Every map, score and count on this site comes from a public API, and you can build on it.
        Pull the habitat model for any fungus into R, Python, a field app or another database —
        the same routes this site uses, documented here from the file the server itself is tested
        against.
      </PageHeader>
      <Page>
        <div className="grid gap-8 lg:grid-cols-[14rem_1fr]">
          <aside className="hidden lg:block">
            <nav className="sticky top-24 space-y-4 text-sm" aria-label="API reference">
              <a href="#start" className="block text-[#4a3728] hover:text-myco-green">Getting started</a>
              <a href="#tokens" className="block text-[#4a3728] hover:text-myco-green">Access and tokens</a>
              {byTag.map((tag) => (
                <div key={tag.name}>
                  <div className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{tag.name}</div>
                  <ul className="mt-1 space-y-1">
                    {tag.endpoints.map((e) => (
                      <li key={e.path}>
                        <a href={`#${anchor(e)}`} className="block truncate font-mono text-xs text-[#5c4a3a] hover:text-myco-green">
                          {e.path.replace(/^\/api/, "")}
                        </a>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
              <a href="#open" className="block text-[#4a3728] hover:text-myco-green">Keeping it open</a>
            </nav>
          </aside>

          <div className="min-w-0 space-y-10">
            <section id="start" className="scroll-mt-24 space-y-4">
              <SectionTitle>Getting started</SectionTitle>
              <div className="grid gap-5 sm:grid-cols-2">
                <Fact icon={Server} label="Base URL">
                  <code className="font-mono">{PUBLIC_BASE}/api</code>. Everything is a{" "}
                  <code>GET</code>; nothing on this API changes data.
                </Fact>
                <Fact icon={Braces} label="Format">
                  JSON, except maps, which are PNG. Taxon names go in the path percent-encoded,
                  quotes and all.
                </Fact>
                <Fact icon={FileJson} label="OpenAPI 3.1">
                  <a href="/api/openapi.json" className="text-myco-green hover:underline">/api/openapi.json</a>{" "}
                  — feed it to a client generator, Postman or an AI assistant.
                </Fact>
                <Fact icon={Scale} label="Terms">
                  Code is GPL-3.0-or-later. Cite the release fingerprint from{" "}
                  <a href="#getStatus" className="text-myco-green hover:underline">/api/status</a> alongside any
                  map you use. Collection points are never served finer than 0.1°.
                </Fact>
              </div>
              <QuickStart />
            </section>

            <section id="tokens" className="scroll-mt-24 space-y-4">
              <SectionTitle>Access and tokens</SectionTitle>
              <div className="max-w-3xl space-y-3 text-sm text-[#5c4a3a] leading-relaxed">
                <p>
                  <strong className="text-[#4a3728]">Reading is open: you do not need a token.</strong>{" "}
                  Every caller has a rate limit, so one busy script cannot slow the site for everyone
                  else. Anonymous callers are counted per address; a token is counted on its own and
                  gets a much higher limit.
                </p>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full max-w-xl text-sm">
                  <thead className="text-xs uppercase tracking-wider text-muted-foreground">
                    <tr className="border-b">
                      <th className="px-3 py-2 text-left font-medium">Caller</th>
                      <th className="px-3 py-2 text-right font-medium">Requests per minute</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      ["No token", RATES.anonymous, "per address"],
                      ["Token", RATES.standard, "per token"],
                      ["Bulk token", RATES.bulk, "on request, for big jobs"],
                    ].map(([label, rate, note]) => (
                      <tr key={String(label)} className="border-b last:border-0">
                        <td className="px-3 py-2 text-[#4a3728]">
                          {label} <span className="text-xs text-muted-foreground">{note}</span>
                        </td>
                        <td className="px-3 py-2 text-right tabular-nums">{Number(rate).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <Card>
                <CardContent className="flex flex-col gap-4 p-5 sm:flex-row sm:items-start">
                  <KeyRound className="h-8 w-8 shrink-0 text-myco-green" />
                  <div className="min-w-0 space-y-3 text-sm text-[#5c4a3a] leading-relaxed">
                    <p>
                      Tokens are issued through your <strong className="text-[#4a3728]">mycomap.org</strong>{" "}
                      account, so there is no separate Atlas login. Say what you will use it for, a
                      MycoMap admin approves it, and you send it with each request:
                    </p>
                    <Code>{`curl -H "X-API-Key: atlas_…" "${PUBLIC_BASE}/api/models"`}</Code>
                    <p>
                      Every response says where you stand in <code>X-RateLimit-Limit</code>,{" "}
                      <code>X-RateLimit-Remaining</code> and <code>X-Atlas-Tier</code>. Over the limit
                      you get <code>429</code> with <code>Retry-After</code> in seconds. A token that is
                      unknown, still pending, disabled or revoked gets <code>401</code> with the reason,
                      rather than being quietly served at the anonymous rate.
                    </p>
                    <a
                      href={TOKEN_REQUEST_URL}
                      className="inline-flex items-center gap-2 rounded-md bg-myco-green px-4 py-2 font-semibold text-white hover:bg-myco-green/90"
                    >
                      Request a token on mycomap.org <ArrowUpRight className="h-4 w-4" />
                    </a>
                    <label className="block pt-2 text-xs text-muted-foreground">
                      Have one? Paste it to use it in the Try it panels below. It stays in this tab only.
                      <input
                        type="password"
                        autoComplete="off"
                        value={token}
                        onChange={(event) => setToken(event.target.value.trim())}
                        placeholder="atlas_…"
                        className="mt-1 h-9 w-full max-w-sm rounded-md border border-input bg-white px-2 font-mono text-sm text-foreground"
                      />
                    </label>
                  </div>
                </CardContent>
              </Card>
            </section>

            {byTag.map((tag) => (
              <section key={tag.name} className="space-y-4">
                <div>
                  <SectionTitle>{tag.name}</SectionTitle>
                  {tag.description && <p className="-mt-2 text-sm text-muted-foreground">{tag.description}</p>}
                </div>
                {tag.endpoints.map((e) => (
                  <EndpointCard key={e.path} endpoint={e} token={token} />
                ))}
              </section>
            ))}

            <section id="open" className="scroll-mt-24">
              <SectionTitle>Keeping it open</SectionTitle>
              <div className="max-w-3xl space-y-3 text-sm text-[#5c4a3a] leading-relaxed">
                <p>
                  This page is drawn from <code>inst/api/openapi.json</code> in the Atlas repository,
                  and the server hands out the same file. A test reads the server's routes from its own
                  source and fails if any route or parameter is missing from that file, or if the file
                  describes one the server no longer has. The documentation cannot fall behind the code
                  without the build going red.
                </p>
                <p>
                  To add a route, add it to <code>inst/plumber/atlas.R</code> and describe it in{" "}
                  <code>openapi.json</code> in the same pull request. Run your own copy with{" "}
                  <code>./atlas api</code>; everything here works against it.
                </p>
                <a
                  href={GITHUB_URL}
                  className="inline-flex items-center gap-2 rounded-md border border-[#A87146]/20 px-3 py-2 font-medium text-[#4a3728] hover:border-myco-green hover:text-myco-green"
                >
                  <GithubMark /> BiodiverseLabs/mycomap-atlas <ArrowUpRight className="h-3.5 w-3.5" />
                </a>
              </div>
            </section>
          </div>
        </div>
      </Page>
    </>
  );
}
