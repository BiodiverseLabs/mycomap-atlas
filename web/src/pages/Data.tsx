import { useQuery } from "@tanstack/react-query";
import { Link } from "wouter";

import { ApiDown, Loading, Stat, Th } from "@/components/Common";
import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getLayers, getStatus, getTaxaCount } from "@/lib/api";
import { formatNumber, formatWhen } from "@/lib/utils";

// About 20 independent localities is where a map becomes worth drawing.
const THRESHOLDS = [5, 10, 20, 30, 50, 100];
const PUBLISH_AT = 20;

export default function Data() {
  const status = useQuery({ queryKey: ["status"], queryFn: getStatus });
  const layers = useQuery({ queryKey: ["layers"], queryFn: () => getLayers("draft") });
  const readiness = useQuery({
    queryKey: ["readiness"],
    enabled: status.data?.ready === true,
    queryFn: async () =>
      Promise.all(
        THRESHOLDS.map(async (threshold) => ({ threshold, taxa: await getTaxaCount(threshold) })),
      ),
  });

  return (
    <>
      <PageHeader title="Data">
        What the maps are built from: MycoMap collections confirmed by DNA, and environmental
        layers that cover all of North America on an equal-area grid, so a cell means the same
        ground in Oaxaca and in Nunavut.
      </PageHeader>
      <Page>
        {status.isError && <ApiDown />}

        <section>
          <SectionTitle>Training records</SectionTitle>
          <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
            A record counts when it is green in at least one MycoMap validation project and red in
            none, has coordinates accurate to 1 km or better, and carries a species-level name —
            provisional names included, since a third of the mappable taxa have no formal name
            yet. Unassessed records, photo identifications and eDNA are left out.
          </p>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label="Records" value={formatNumber(status.data?.records)} />
            <Stat label="Taxa" value={formatNumber(status.data?.taxa)} />
            <Stat label="Last pull" value={formatWhen(status.data?.pulledAt).split(",")[0]} />
            <Stat label="Fingerprint" value={status.data?.fingerprint?.slice(0, 12) ?? "—"} />
          </div>

          <Card className="mt-4 max-w-xl">
            <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
              <CardTitle className="text-base text-[#4a3728]">How many taxa could be mapped</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <table className="w-full text-sm">
                <thead className="text-xs uppercase tracking-wider text-muted-foreground">
                  <tr className="border-b">
                    <Th>Independent localities</Th>
                    <Th right>Taxa</Th>
                  </tr>
                </thead>
                <tbody>
                  {readiness.isLoading && (
                    <tr>
                      <td className="px-4 py-3 text-muted-foreground" colSpan={2}>
                        Counting…
                      </td>
                    </tr>
                  )}
                  {readiness.data?.map((row) => (
                    <tr
                      key={row.threshold}
                      className={`border-b last:border-0 ${row.threshold === PUBLISH_AT ? "bg-myco-green/10" : ""}`}
                    >
                      <td className="px-4 py-2">
                        {row.threshold} or more
                        {row.threshold === PUBLISH_AT && (
                          <span className="ml-2 text-xs text-myco-green">enough for a map</span>
                        )}
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatNumber(row.taxa)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardContent>
          </Card>
        </section>

        <section>
          <SectionTitle>Environmental layers</SectionTitle>
          <p className="mb-4 max-w-3xl text-sm text-[#5c4a3a] leading-relaxed">
            Every source is global, because the familiar United States products stop at the
            border while British Columbia alone holds 8% of the records. The cost: no continental
            map of tree species exists, so tree cover is carried as a fraction, and a model
            cannot be read as knowing which host a fungus needs.
          </p>
          {layers.isLoading && <Loading />}
          <div className="grid gap-4 md:grid-cols-2">
            {(layers.data?.layers ?? []).map((layer) => (
              <Card key={layer.id}>
                <CardHeader className="bg-[#f8f5f0] border-b border-[#A87146]/10 py-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <CardTitle className="text-base text-[#4a3728]">{layer.title}</CardTitle>
                    <Badge variant={layer.built ? "default" : "secondary"}>
                      {layer.built ? "built" : "not built"}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent className="p-4 space-y-2 text-sm">
                  <p className="text-[#5c4a3a]">
                    {layer.url ? (
                      <a href={layer.url} target="_blank" rel="noreferrer" className="text-myco-green hover:underline">
                        {layer.source}
                      </a>
                    ) : (
                      layer.source
                    )}{" "}
                    · <span className="text-muted-foreground">{layer.license}</span>
                  </p>
                  {layer.built && (
                    <p className="text-xs text-muted-foreground tabular-nums">
                      {formatNumber(layer.bands?.length)} band{layer.bands?.length === 1 ? "" : "s"} ·{" "}
                      {formatNumber(layer.cellSizeM)} m cells · {layer.sizeMb} MB · built{" "}
                      {formatWhen(layer.builtAt).split(",")[0]}
                    </p>
                  )}
                  {layer.bands && layer.bands.length > 0 && (
                    <div className="flex flex-wrap gap-1">
                      {layer.bands.map((band) => (
                        <span
                          key={band}
                          className="rounded border border-[#A87146]/20 px-1.5 py-0.5 text-xs text-muted-foreground"
                        >
                          {band}
                        </span>
                      ))}
                    </div>
                  )}
                  <p className="text-xs text-muted-foreground">{layer.citation}</p>
                </CardContent>
              </Card>
            ))}
          </div>
          <p className="mt-4 text-sm text-[#5c4a3a]">
            Every dataset, package and intermediate file, with links and what is published:{" "}
            <Link href="/sources" className="text-myco-green hover:underline">
              Data and sources
            </Link>
            .
          </p>
        </section>
      </Page>
    </>
  );
}
