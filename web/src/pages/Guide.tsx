import type { CSSProperties, ReactNode } from "react";
import { Link } from "wouter";

import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { gradeNote } from "@/lib/grade";
import { usePageMeta } from "@/lib/usePageMeta";

// How to read a map, for a first-time visitor (Steve, 2026-10-08). Linked from
// every taxon page. Short and honest: what the colours mean, what a faint map
// says, where a map makes no claim, and what a map is not. The faint maps'
// notes come from lib/grade.ts, so this page and the maps never disagree.

const RANK = "linear-gradient(to right, #f7f7e8, #94c440, #2e5a17)";
const HATCH = "repeating-linear-gradient(135deg, rgba(140,140,125,0.55) 0 2px, rgba(140,140,125,0.12) 2px 6px)";

/** A small drawn sample: what a part of a map looks like. */
function Swatch({ style, label }: { style: CSSProperties; label: string }) {
  return (
    <span
      role="img"
      aria-label={label}
      className="inline-block h-10 w-full max-w-[220px] shrink-0 rounded border border-[#A87146]/20"
      style={style}
    />
  );
}

function Item({ sample, title, children }: { sample: ReactNode; title: string; children: ReactNode }) {
  return (
    <div className="grid gap-3 sm:grid-cols-[220px_1fr] sm:items-start">
      <div>{sample}</div>
      <div className="min-w-0">
        <h3 className="font-semibold text-[#4a3728]">{title}</h3>
        <div className="mt-1 space-y-2 text-[#5c4a3a] leading-relaxed">{children}</div>
      </div>
    </div>
  );
}

function Dots() {
  return (
    <span
      role="img"
      aria-label="White dots: collections"
      className="relative inline-block h-10 w-full max-w-[220px] rounded border border-[#A87146]/20"
      style={{ background: RANK }}
    >
      {[18, 46, 61, 83].map((left, i) => (
        <span
          key={left}
          className="absolute h-2.5 w-2.5 rounded-full border border-[#4a3728] bg-white"
          style={{ left: `${left}%`, top: i % 2 ? "28%" : "52%" }}
        />
      ))}
    </span>
  );
}

export default function Guide() {
  usePageMeta({
    title: "How to read a map",
    description:
      "What the colours on an Atlas habitat map mean, what a faint map says, where a map makes no claim, and what a map is not.",
  });
  return (
    <>
      <PageHeader title="How to read a map">
        Every taxon page shows one or more habitat maps. This page says what their colours, dots
        and shading mean, in a few minutes&rsquo; reading.
      </PageHeader>
      <Page>
        <section className="max-w-3xl space-y-6">
          <SectionTitle>The colours</SectionTitle>
          <Item sample={<Swatch style={{ background: RANK }} label="Pale to dark green: lowest to highest rated ground" />} title="Pale to dark green: how well each place suits the fungus">
            <p>
              Each place is rated by how closely its climate, soil and trees match the places
              where this fungus has been confirmed by DNA. The colours are ranks within the
              fungus&rsquo;s own range: the darkest green is the tenth of the ground its map rates
              highest. So two species&rsquo; maps can be compared side by side, but a dark cell
              means &ldquo;among the best for this species&rdquo;, not a fixed amount of habitat.
            </p>
          </Item>
          <Item sample={<Dots />} title="White dots: where it has been collected">
            <p>
              Each dot is a cell of 0.1&deg; (about 11 km) holding one or more DNA-validated
              collections; bigger dots hold more. Exact collection sites are never shown.
            </p>
          </Item>
          <Item sample={<Swatch style={{ background: HATCH }} label="Hatched: conditions unlike any surveyed site" />} title="Hatched: no data like it">
            <p>
              Hatching marks conditions unlike any site where collections were surveyed, so the
              map has nothing to learn from there and makes no claim. Colour also stops about
              500 km from the nearest record.
            </p>
          </Item>
        </section>

        <section className="max-w-3xl space-y-6">
          <SectionTitle>Strong and faint maps</SectionTitle>
          <p className="text-[#5c4a3a] leading-relaxed">
            Every map is tested on ground it never saw, and against stand-in maps built from
            collections shifted across the landscape, which keep the same clustering as real
            collecting. That test decides how a map is drawn.
          </p>
          <Item sample={<Swatch style={{ background: RANK }} label="A strong map, drawn at full strength" />} title="Strong: drawn at full strength">
            <p>
              The map beat clustered collecting. Only strong maps make claims anywhere on the
              site: in &ldquo;What could grow here?&rdquo;, in the states and provinces a species
              is likely in, and in the combined map.
            </p>
          </Item>
          <Item sample={<Swatch style={{ background: RANK, opacity: 0.25 }} label="A weak map, drawn faint" />} title="Weak: drawn faint, read as a hint">
            <p>Shown faint on its taxon page only, with this note:</p>
            <p className="rounded bg-[#f8f5f0] px-3 py-2 text-sm italic">{gradeNote("weak")}</p>
          </Item>
          <Item sample={<Swatch style={{ background: RANK, opacity: 0.25 }} label="A failed map, drawn faint" />} title="Failed: drawn faint, says little">
            <p>Shown faint on its taxon page only, with this note:</p>
            <p className="rounded bg-[#f8f5f0] px-3 py-2 text-sm italic">{gradeNote("failed")}</p>
          </Item>
          <p className="text-[#5c4a3a] leading-relaxed">
            Under each map, <strong>Map strength</strong> sets how strongly it is drawn. It starts
            where the test puts it, and you can turn a faint map up to look at it, or a strong one
            down to see the ground beneath.
          </p>
        </section>

        <section className="max-w-3xl space-y-4">
          <SectionTitle>Several maps of one species</SectionTitle>
          <p className="text-[#5c4a3a] leading-relaxed">
            A well-collected species gets up to three maps from different methods, fitted to the
            same records, side by side; a sparsely collected one gets a single map averaged from
            many small models. Where the methods agree, trust the pattern more.
          </p>
          <p className="text-[#5c4a3a] leading-relaxed">
            When a species has two or more strong maps, its page also shows them together:
            the <strong>combined map</strong> averages them, giving more weight to the better
            tested, and <strong>where they disagree</strong> shades the places the methods rate
            differently. Disagreement is honest uncertainty, not an error.
          </p>
        </section>

        <section className="max-w-3xl space-y-3 rounded-lg border border-[#A87146]/20 bg-[#f8f5f0] p-5">
          <SectionTitle>What a map is not</SectionTitle>
          <ul className="list-disc space-y-2 pl-5 text-[#5c4a3a] leading-relaxed">
            <li>
              <strong>Suitable habitat, not a sighting.</strong> A dark cell says the ground suits
              the fungus, not that it grows there or how common it is.
            </li>
            <li>
              <strong>Not for foraging or safety.</strong> Never use a map to decide what is safe to
              eat or where to pick, or for permits, land management or other regulatory decisions.
            </li>
            <li>
              <strong>Provisional names can change.</strong> A name with a code, such as
              Mycena sp. &lsquo;IN10&rsquo;, is a DNA lineage without a published name yet. It may
              be renamed, split or merged, and its map changes with it.
            </li>
          </ul>
        </section>

        <section className="max-w-3xl text-[#5c4a3a] leading-relaxed">
          <p>
            More detail on how the maps are made and tested is in{" "}
            <Link href="/methods" className="text-myco-green underline-offset-2 hover:underline">
              Methods
            </Link>
            . To see a map, search for a species or{" "}
            <Link href="/maps" className="text-myco-green underline-offset-2 hover:underline">
              browse the maps
            </Link>
            .
          </p>
        </section>
      </Page>
    </>
  );
}
