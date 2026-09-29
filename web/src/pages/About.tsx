import type { ReactNode } from "react";

import { PageHeader } from "@/components/Layout";

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="font-display text-2xl text-[#4a3728] mb-2">{title}</h2>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

export default function About() {
  return (
    <>
      <PageHeader title="How it works">
        A habitat map for a fungus answers one question: given the climate, soil and cover of a
        place, how much does it resemble the places this species has been found?
      </PageHeader>
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8 max-w-3xl space-y-8 text-[#5c4a3a] leading-relaxed">
        <Section title="Only names confirmed by DNA">
          <p>
            Every map is trained on MycoMap collections whose identity was confirmed by
            sequencing and validated in a MycoMap project. Photo identifications, herbarium names
            and unassessed records are left out: an old species concept can be wrong even after
            its synonyms are sorted out, and a model trained on a wrong name draws a confident
            wrong map.
          </p>
          <p>
            Provisional names such as <span className="sci">Mycena</span> sp. &lsquo;IN10&rsquo;
            are included. They are codes for DNA clusters, not ranges, and about a third of the
            taxa with enough records to map have no formal name yet. A map belongs to the set of
            records behind it, so when records move between names, the map is refitted.
          </p>
        </Section>

        <Section title="Compared with where people collect">
          <p>
            Six states and provinces hold 61% of the records, and Indiana alone holds 12%. Compared
            with random points across the continent, almost every fungus would appear to love
            Indiana&rsquo;s climate, because that is where the sequencing happened.
          </p>
          <p>
            So each species is compared with every other DNA-validated collection instead. Those
            share the same bias, because somebody collected, sequenced and validated them too, and
            the model learns what makes this fungus different from fungi in general in the places
            people look.
          </p>
        </Section>

        <Section title="Three models, side by side">
          <p>
            Every map is drawn three ways from the same records, against the same background.{" "}
            <strong className="text-[#4a3728]">Maxent</strong> fits smooth responses to each
            variable and is the long-standing standard for data like these.{" "}
            <strong className="text-[#4a3728]">Boosted trees</strong> build hundreds of small
            decision trees, each correcting the last, and can find combinations of conditions a
            smooth curve cannot. A <strong className="text-[#4a3728]">random forest</strong> grows
            a thousand trees independently, each on as many background records as presences, and
            lets them vote.
          </p>
          <p>
            None is right by default. Where the three agree, the pattern is in the records; where
            they part company, the map is saying more about the model than about the fungus. The{" "}
            <a href="/models" className="text-myco-green hover:underline">Models page</a> shows how
            they compare across every well-recorded taxon.
          </p>
          <p>
            Each map is coloured by rank within its own ground, not by its raw score: the darkest
            green is the tenth of the area that model rates highest. The three models put their
            scores on different scales, and ranking is what lets them be read side by side.
          </p>
        </Section>

        <Section title="Why the colour stops in circles">
          <p>
            A map covers the ground within 500 km of the species&rsquo; records and no further. A
            fungus is not absent from Yukon because nobody has looked there, and a model should
            not be asked about ground its subject could never have reached. Where the colour
            ends, the map is silent rather than saying &ldquo;unsuitable&rdquo;.
          </p>
        </Section>

        <Section title="Tested on regions it never saw">
          <p>
            Collections come in clusters: one foray can yield thirty from a single wood. Holding
            out random records would leave near neighbours on both sides and flatter the model.
            Instead the continent is cut into 200 km blocks, and each map is scored on whole
            blocks it was not trained on.
          </p>
          <p>
            Two scores are shown. <strong className="text-[#4a3728]">Blocked AUC</strong> says how
            well the map separates this fungus from other collections; 0.5 is chance. A
            generalist that grows wherever people look scores near 0.5 by nature, which is the
            honest answer. <strong className="text-[#4a3728]">Boyce</strong> asks whether places
            the map rates higher really hold more records; it runs from &minus;1 to 1, and is
            unsteady below about 50 records.
          </p>
        </Section>

        <Section title="How much data a map needs">
          <p>
            A map needs records from about 20 separate 5 km cells. Record counts can mislead: a
            species with 105 records all from one town park has one population, not 105. Below
            the threshold a taxon is a survey target, and every sequenced collection from a new
            place brings its map closer.
          </p>
          <p>
            Sparse species are given fewer environmental variables, roughly one for every four
            records, chosen in an order a mycologist would recognise: moisture first, then
            temperature, then what the fungus grows on, then soil, then the shape of the ground.
          </p>
        </Section>

        <Section title="What these maps are not">
          <p>
            They are habitat suitability, not occurrence: a high value means a place resembles
            where the species has been found, not that it is there. No continental map of tree
            species exists, so the models know how wooded a place is but not which trees grow
            there. These are early maps on a 5 km grid; releases will be built at 1 km.
          </p>
        </Section>
      </div>
    </>
  );
}
