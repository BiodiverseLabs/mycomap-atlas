import { Link } from "wouter";

import { Page, PageHeader } from "@/components/Layout";
import { usePageMeta } from "@/lib/usePageMeta";

/**
 * Any address the app does not know. noindex keeps a mistyped or retired
 * address out of search results, even while the server still answers it with
 * the app and a 200.
 */
export default function NotFound() {
  usePageMeta({
    title: "Page not found",
    description: "There is nothing at this address on MycoMap Atlas.",
    noindex: true,
  });
  return (
    <>
      <PageHeader title="Page not found" />
      <Page>
        <p className="text-muted-foreground">
          There is nothing at this address. Try the search box above, or{" "}
          <Link href="/taxa" className="text-myco-green hover:underline">
            every taxon
          </Link>
          .
        </p>
      </Page>
    </>
  );
}
