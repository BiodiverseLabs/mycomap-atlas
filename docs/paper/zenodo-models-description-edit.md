# Zenodo models record description edit: APPROVED by Steve 2026-10-21

*The operations lane applies it with Steve's direct OK. The lineage table
(below, "Optional") goes into the next models deposit version, bundled
with the E19 and E20 tables (Steve, 2026-10-21).*

*Drafted 2026-10-21 by the paper lane; corrected the same day after the
method lane's review. Nothing goes to Zenodo without Steve's explicit OK
for this record. Metadata only: no file, DOI or version changes.*

**Record.** doi:10.5281/zenodo.23463939, "MycoMap Atlas: habitat models for
North American fungi (draft grid)".

**Why.** The description says "Records: 133235 DNA-validated collections,
16252 taxa, pulled 2026-10-12T05:17:58Z". Those counts are the published
records and taxa, after 76 erroneous records were removed by an exclusion
list. Most models in the record were fitted on the same 2026-10-12 pull
before that list was applied (E3 prereg, Deviations, 2026-10-21). A reader
would assume the models were fitted on exactly the 133,235 records, and a
refit from the published counts' pull does not reproduce every model's
folds.

**Proposed addition**, after the "Records:" line:

> These counts are after 76 erroneous records were removed by an exclusion
> list on 2026-10-13 (22 Mushroom Observer records whose number had been
> stored as an iNaturalist link, so they carried an unrelated iNaturalist
> observation's taxon and place, and 54 records named by a non-fungal DNA
> sequence). Most models were fitted on the same 2026-10-12 pull before
> that removal, and 7 on it less the 22. No removed record trained a
> published model as a presence: the taxa they named were refitted without
> them or retired. They remain among other taxa's background survey sites
> (under 0.06% of the pull's records). An exact refit needs each model's
> own fitting pull; Atlas's job records, which are not part of this
> deposit, name it for each model.

**Checked by the method lane (2026-10-21):** 133,235 records and 16,252
taxa are the cleaned pull's counts in release.json; the pulled time is the
pull's own (the cleaning kept it); 7 models were fitted on the pull less the
22; 76 of the original pull's 133,311 records is 0.057%. The deposit's
release.json names only the retirement job (which fitted nothing), and
neither its index nor the metrics name a fitting job, so the edit does not
claim the deposit records it.

**Optional, Steve's choice (a new deposit version, not a metadata edit):**
add a lineage table (algorithm, taxon, fitting job, pull sha256) so the
deposit is self-contained. Three pull identities cover every model: the
original 2026-10-12 pull (sha256 4b1f5629…) for R_main and the full-view
refresh; 52d8ad89… (the -x2dd5cb30 pull) for the targeted job's 7 models;
and 7d3c5d70… (-x73b85b36), the pull behind the published counts.
