import type { ReactNode } from "react";

import { Page, PageHeader, SectionTitle } from "@/components/Layout";
import { GITHUB_URL } from "@/lib/contract";
import { usePageMeta } from "@/lib/usePageMeta";

// What a visit leaves behind, here and with the services the pages call. Keep
// it true: when the site starts storing or sending something new, say so here
// in the same change. The cookies are R/auth.R's; the web logs are nginx's
// (deploy/lightsail); the tiles are OpenStreetMap's (the Leaflet maps).

function A({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} className="text-myco-green underline-offset-2 hover:underline">
      {children}
    </a>
  );
}

export default function Privacy() {
  usePageMeta({
    title: "Privacy",
    description:
      "What a visit to MycoMap Atlas leaves behind: no analytics, a cookie only if you sign in, and what Cloudflare and OpenStreetMap see.",
  });
  return (
    <>
      <PageHeader title="Privacy">
        Atlas has nothing to sell and no one to sell it to. This page says what a visit leaves
        behind, on this site and with the services its pages use.
      </PageHeader>
      <Page>
        <section className="max-w-3xl space-y-3 text-[#3d3027] leading-relaxed">
          <SectionTitle>What Atlas keeps</SectionTitle>
          <ul className="list-disc pl-5 space-y-2">
            <li>
              <strong>No analytics, no advertising, no tracking.</strong> Browsing the site sets no
              cookie and stores nothing in your browser.
            </li>
            <li>
              <strong>A cookie only if you sign in.</strong> Signing in with a mycomap.org account
              sets a ten-minute cookie while mycomap.org confirms who you are, then a session
              cookie holding your mycomap.org account number and name, signed so it cannot be
              altered. It lasts two weeks or until you sign out. Atlas has no accounts and no
              record of people beyond that cookie, which lives in your browser.
            </li>
            <li>
              <strong>Web server logs.</strong> Atlas&rsquo;s web server records each request:
              your network address, the address asked for, the time and your browser&rsquo;s name.
              They are used to find faults and stop abuse, and are deleted after about two weeks.
              To enforce the API&rsquo;s rate limit, the server counts requests per address in
              memory and forgets an address after ten quiet minutes.
            </li>
            <li>
              <strong>&ldquo;What could grow here?&rdquo;</strong> sends Atlas&rsquo;s API the
              point you click on the map, or your browser&rsquo;s location if you press &ldquo;Use
              my location&rdquo;, to about 10 m. Your browser asks before it shares a location.
              The point is part of the request, so it is in the web logs above; it is not stored
              anywhere else.
            </li>
          </ul>
        </section>

        <section className="max-w-3xl space-y-3 text-[#3d3027] leading-relaxed">
          <SectionTitle>What others see</SectionTitle>
          <ul className="list-disc pl-5 space-y-2">
            <li>
              <strong>Cloudflare</strong> carries every request to this site and protects it, so it
              sees your address and what you ask for (
              <A href="https://www.cloudflare.com/privacypolicy/">Cloudflare&rsquo;s privacy policy</A>).
            </li>
            <li>
              <strong>Map backgrounds</strong> come from{" "}
              <A href="https://www.openstreetmap.org/copyright">OpenStreetMap</A>&rsquo;s tile
              servers. Your browser fetches the tiles for the area on screen, so the OpenStreetMap
              Foundation sees your address and roughly where you are looking. It is told the site
              you came from, never the page or the fungus (
              <A href="https://osmfoundation.org/wiki/Privacy_Policy">its privacy policy</A>).
            </li>
            <li>
              <strong>Fonts</strong> are served from this site. Nothing is fetched from Google or
              any other font service.
            </li>
            <li>
              <strong>Signing in</strong> takes you to mycomap.org and back; mycomap.org&rsquo;s
              own terms apply while you are there. Links to GitHub, mycomap.org and the data
              sources are ordinary links: nothing is sent to them unless you follow one.
            </li>
          </ul>
        </section>

        <section className="max-w-3xl space-y-3 text-[#3d3027] leading-relaxed">
          <SectionTitle>Questions</SectionTitle>
          <p>
            Write to <A href="mailto:info@mycomap.org">info@mycomap.org</A>. A map
            that shows a collection site too precisely is a different matter: report it privately,
            as <A href={`${GITHUB_URL}/security/policy`}>the
            security policy</A> asks.
          </p>
        </section>
      </Page>
    </>
  );
}
