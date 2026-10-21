# Proposed edit: Zenodo models record description (for Steve)

*Drafted 2026-10-21 by the paper lane. Nothing goes to Zenodo without
Steve's explicit OK for this record. Metadata only: no file, DOI or
version changes.*

**Record.** doi:10.5281/zenodo.23463939, "MycoMap Atlas: habitat models for
North American fungi (draft grid)".

**Why.** The description says "Records: 133235 DNA-validated collections,
16252 taxa, pulled 2026-10-12T05:17:58Z". Those counts are the published
records and taxa, after 76 erroneous records were removed by an exclusion
list. Most models in the record were fitted on the same 2026-10-12 pull
before that list was applied (E3 prereg, Deviations, 2026-10-21). A reader
would assume the models were fitted on exactly the 133,235 records, and a
refit from the published pull alone does not reproduce every model's folds.

**Proposed addition**, after the "Records:" line:

> These counts are after 76 erroneous records (non-fungal host or
> contaminant sequences, and records filed under the wrong source) were
> removed by an exclusion list on 2026-10-13. Most models were fitted on
> the same 2026-10-12 pull before that removal, and 7 on it less 22 of
> those records. No removed record trained a published model as a
> presence: the taxa they named were refitted without them or retired.
> They remain among other taxa's background survey sites (under 0.06% of
> records). An exact refit uses each model's fitting-job inputs, which
> the release's metadata records.

[CHECK before sending: the phrase "records filed under the wrong source"
for the 22 first-cleaning rows (the bogus "iNat<number>" Mushroom Observer
rows), and that the release metadata in the deposit names each model's
fitting job.]
