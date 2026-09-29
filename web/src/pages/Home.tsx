import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useLocation } from "wouter";
import { Dna, Mountain, Search, SquareDashed } from "lucide-react";

import { ApiDown, Stat } from "@/components/Common";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { getModels, getStatus, getTaxa } from "@/lib/api";
import { formatNumber } from "@/lib/utils";

function useDebounced<T>(value: T, ms: number): T {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setSettled(value), ms);
    return () => clearTimeout(timer);
  }, [value, ms]);
  return settled;
}

function SpeciesSearch({ mapped }: { mapped: Set<string> }) {
  const [text, setText] = useState("");
  const [, navigate] = useLocation();
  const search = useDebounced(text.trim(), 200);
  const results = useQuery({
    queryKey: ["search", search],
    enabled: search.length >= 2,
    queryFn: () => getTaxa({ search, limit: 8 }),
  });
  const open = (name: string) => navigate(`/taxa/${encodeURIComponent(name)}`);
  const items = results.data?.items ?? [];

  return (
    <div className="relative max-w-xl">
      <Search className="absolute left-3 top-3 h-5 w-5 text-muted-foreground" />
      <input
        value={text}
        onChange={(event) => setText(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter" && items.length) open(items[0].scientific_name);
        }}
        placeholder="Find a fungus, e.g. Trametes versicolor"
        className="h-11 w-full rounded-md border border-[#A87146]/20 bg-white pl-10 pr-3 text-base outline-none focus:ring-2 focus:ring-myco-green"
        aria-label="Search for a taxon"
      />
      {search.length >= 2 && (
        <div className="absolute z-20 mt-1 w-full overflow-hidden rounded-lg border border-gray-100 bg-white shadow-lg">
          {results.isLoading && <p className="px-4 py-3 text-sm text-muted-foreground">Searching…</p>}
          {results.data && !items.length && (
            <p className="px-4 py-3 text-sm text-muted-foreground">No validated records under that name.</p>
          )}
          {items.map((taxon) => (
            <button
              key={taxon.scientific_name}
              type="button"
              onClick={() => open(taxon.scientific_name)}
              className="flex w-full items-center justify-between gap-3 px-4 py-2 text-left hover:bg-myco-green/5"
            >
              <span className="sci">{taxon.scientific_name}</span>
              <span className="flex items-center gap-2 text-xs text-muted-foreground">
                {formatNumber(taxon.records)} records
                {mapped.has(taxon.scientific_name) && <Badge>map</Badge>}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

const PRINCIPLES = [
  {
    icon: Dna,
    title: "DNA-validated records only",
    text: "Every map is trained on collections whose identity was confirmed by sequencing, never on photo IDs or old herbarium names.",
  },
  {
    icon: SquareDashed,
    title: "Compared with where people collect",
    text: "A map is drawn against every other sequenced collection, so it learns the fungus's habitat rather than where MycoMap members happen to live.",
  },
  {
    icon: Mountain,
    title: "Tested on regions it never saw",
    text: "Scores come from holding out whole 200 km blocks of the continent, not scattered points, so a model cannot pass by memorising one wood.",
  },
];

export default function Home() {
  const status = useQuery({ queryKey: ["status"], queryFn: getStatus });
  const models = useQuery({ queryKey: ["models"], queryFn: getModels });
  const mapped = new Set((models.data ?? []).filter((m) => m.map).map((m) => m.taxon));

  return (
    <>
      <PageHeader title="Where fungi can grow">
        Habitat maps for North American fungi, built only from MycoMap collections whose names
        were confirmed by DNA. Find a species to see where its records are and where the model
        thinks it could be found.
      </PageHeader>
      <Page>
        {status.isError ? (
          <ApiDown />
        ) : (
          <>
            <SpeciesSearch mapped={mapped} />

            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Stat label="Validated records" value={formatNumber(status.data?.records)} />
              <Stat label="Taxa" value={formatNumber(status.data?.taxa)} />
              <Stat label="Taxa with a map" value={models.data ? formatNumber(mapped.size) : "—"} />
              <Stat label="Grid" value="5 km" hint="draft" />
            </div>

            <section>
              <SectionTitle>How the maps are made</SectionTitle>
              <div className="grid gap-4 md:grid-cols-3">
                {PRINCIPLES.map(({ icon: Icon, title, text }) => (
                  <Card key={title}>
                    <CardContent className="p-5">
                      <Icon className="h-6 w-6 text-myco-green" />
                      <h3 className="mt-3 font-semibold text-[#4a3728]">{title}</h3>
                      <p className="mt-1 text-sm text-[#5c4a3a] leading-relaxed">{text}</p>
                    </CardContent>
                  </Card>
                ))}
              </div>
              <p className="mt-4 text-sm">
                <Link href="/about" className="text-myco-green hover:underline">
                  More on how it works
                </Link>
                {" · "}
                <Link href="/maps" className="text-myco-green hover:underline">
                  Browse every map
                </Link>
              </p>
            </section>
          </>
        )}
      </Page>
    </>
  );
}
