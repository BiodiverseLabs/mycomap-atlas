# Appendix S1: Section S8. What sequence names change (E9, E16)

*Draft, 2026-11-04. Numbers are copied from the registry entries
`docs/experiments/2026-10-13-plan-e9-record-names.md` (Result) and
`docs/experiments/2026-10-28-e16-descriptives.md` (Part 1), not recomputed
here. E9's design and its decision rule were registered before any fit.*

## S8.1 Design (E9)

Every taxon whose record set differs between DNA names and the records' own
names, on the hindcast's pull (cutoff 2026-08-17), was fitted under both
labellings on one image and processor family (r7i), the record-name model
reusing its DNA pair's spatial block. A job carries one pull, so the two
sides are two private jobs launched together from one commit
(priv-20261026T021038Z-3ba43cf6 and priv-20261026T021038Z-9c0ba509). The
comparison is unchanged by that. The record side reached its 8-hour limit
with one shard unreported; that shard was relaunched on-demand on the same
image and family, resuming from its saved models.

Both sides were scored on E2's later finds with E2's exclusions and refit.
The **primary truth** is each find's DNA name, the validated identity of the
record; this favours the DNA side where names disagree, so each side scored
on its own labelling is a pre-specified **secondary** estimate.

**H9 (two-sided).** The 95% interval of the paired DNA − record-name
difference in top-half share (10,000 resamples of taxa, seed 1) excludes 0.
Above 0: DNA labels give maps that rank later finds better. Including 0: no
detectable difference, and C3 narrows to coverage. Below 0: record names do
better, reported as such.

## S8.2 Result

**H9 does not hold: no detectable difference.**

| Estimate | Difference | 95% interval | Taxa | Models |
|---|---|---|---|---|
| Primary (truth: the find's DNA name) | −0.0027 | −0.0106 to 0.0050 | 550 | 1,176 |
| Secondary (each side on its own labelling) | −0.0038 | −0.0120 to 0.0041 | 547 | 1,173 |

Of the 978 taxa paired at planning, 550 have later finds ranked by models on
both sides; the rest have no ranked later finds under one labelling or the
other.

Primary pairing (top half / top tenth / mean rank / beats effort / Boyce;
new and known places omit Boyce):

| Side | Places | All | New places | Known places |
|---|---|---|---|---|
| DNA | 1,676 | 0.871 / 0.479 / 0.797 / 0.705 / 0.999 | 0.838 / 0.386 / 0.755 / 0.654 | 0.952 / 0.704 / 0.898 / 0.828 |
| Record | 1,670 | 0.874 / 0.479 / 0.796 / 0.703 / 0.995 | 0.841 / 0.383 / 0.755 / 0.652 | 0.952 / 0.710 / 0.896 / 0.824 |

By grade, on the paired models (taxa, places, top half, beats effort):

| Grade | DNA | Record |
|---|---|---|
| strong | 36, 70, 0.891, 0.727 | 41, 92, 0.887, 0.774 |
| weak | 489, 1,584, 0.878, 0.709 | 477, 1,556, 0.881, 0.705 |
| failed | 87, 188, 0.755, 0.637 | 97, 225, 0.774, 0.645 |

## S8.3 The two releases compared (descriptive)

`study-compare` on the two releases decides nothing; H9 is the registered
comparison.

**Records whose label differs** (each record's DNA name against its record
name; the hindcast's 124,955 records). MyCoPortal is one portal under two
mycomap.org source spellings by import date, with no record number under
both, so they are combined here.

| Source | Records | Same | Spelling only | Another species, same genus | Another genus | No species-level record name |
|---|---|---|---|---|---|---|
| iNaturalist | 118,703 | 117,226 | 89 | 1,120 | 238 | 30 |
| Mushroom Observer | 4,593 | 4,207 | 21 | 282 | 39 | 44 |
| MyCoPortal | 1,596 | 970 | 10 | 335 | 184 | 97 |
| mycomap.org sequences | 61 | 57 | 0 | 1 | 2 | 1 |
| GenBank | 2 | 2 | 0 | 0 | 0 | 0 |
| **All** | **124,955** | **122,462** | **120** | **1,738** | **463** | **172** |

DNA names another species or genus for 2,201 records (1.8%): 1.1% of
iNaturalist's, 7.0% of Mushroom Observer's, 32.5% of MyCoPortal's.

**Taxa.** 15,770 under DNA names and 15,633 under record names. 656 DNA taxa
split (their records go to two or more record-name taxa) and 737 record-name
taxa merge two or more DNA taxa; 606 names exist only under DNA names and
469 only under record names. 1,331 taxa changed their record set; 13,833 did
not.

**Models.** 1,852 fitted (52 refused) under DNA names, 1,860 (44 refused)
under record names; 1,702 pairs share taxon and learner. Strong models by
learner (ESM / Maxent / random forest / boosted trees): DNA 43 / 24 / 16 / 1;
record 63 / 22 / 17 / 2. Outside the pairs, 158 record-name models have no DNA
counterpart (5 strong, 95 weak, 58 failed), 44 DNA models belong to taxa with
no record under record names, and 106 to taxa with no record-name model of
the same learner.

**Map agreement**, over the cells both maps give a value (Spearman over 1,700
pairs, since 2 Maxent pairs have a constant map; Schoener's D over 1,702):

| | Pairs | Spearman median (IQR) | 10th pct | Schoener's D median (IQR) | 10th pct |
|---|---|---|---|---|---|
| All | 1,700 / 1,702 | 0.958 (0.892–0.990) | 0.747 | 0.957 (0.918–0.976) | 0.835 |
| ESM | 823 | 0.970 (0.883–0.995) | 0.700 | 0.969 (0.930–0.987) | 0.882 |
| Maxent | 379 / 381 | 0.974 (0.873–0.997) | 0.687 | 0.911 (0.812–0.971) | 0.671 |
| Random forest | 381 | 0.948 (0.916–0.968) | 0.866 | 0.960 (0.952–0.967) | 0.943 |
| Boosted trees | 117 | 0.910 (0.839–0.961) | 0.785 | 0.918 (0.838–0.949) | 0.757 |

Spearman is at least 0.9 in 72.6% of pairs and D in 80.0%; 58 pairs have
Spearman below 0.5. Pairs with the same presence count (287) agree more
(median Spearman 0.987, D 0.979) than pairs with different counts (1,413;
0.951, 0.953). No pair's maps are identical. That is expected from how
backgrounds are built, though E9 did not measure it: a taxon's background
comes from other taxa's records, so relabelling elsewhere changes its training
table even when its own records do not (the mechanism behind E3's 690 kernel
mismatches; Section S10).

**Grades of the 1,702 pairs:**

| DNA \ record | strong | weak | failed |
|---|---|---|---|
| strong (77) | 44 | 32 | 1 |
| weak (1,412) | 54 | 1,267 | 91 |
| failed (212) | 1 | 81 | 130 |
| untested (1) | 0 | 1 | 0 |

1,441 pairs (84.7%) keep their grade; 136 move up, 124 down, and 1 untested
becomes weak. 77 pairs are strong under DNA names and 99 under record names,
and 44 under both. So grades move more than maps do, which is consistent with
the shifted null's low power near its pass line (Section S5). E9 cannot
separate record changes from test-level noise, because no pair was refitted
on identical records; within one processor family a refit on the same records
is bit-identical (Section S10), so this is not noise in the fit itself.

## S8.4 Coverage (E16)

Provisional names are sequence-cluster names with no formal epithet (the
website's rule: quotes, "sp.", or a code). In the frozen release (count /
share of each row's taxa; band sizes in brackets):

| Taxa | All | 1–2 sites | 3–4 | 5–19 | 20–49 | 50–99 | 100+ |
|---|---|---|---|---|---|---|---|
| All 16,252 (by localities) | 9,785 / 60.2% | 6,229 / 66.8% (9,327) | 1,286 / 61.8% (2,081) | 1,776 / 52.1% (3,412) | 402 / 38.2% (1,053) | 79 / 25.9% (305) | 13 / 17.6% (74) |
| Modelled 6,369 (by detection sites) | 3,193 / 50.1% | – | 1,003 / 60.6% (1,655) | 1,739 / 51.5% (3,374) | 375 / 37.1% (1,012) | 65 / 23.6% (276) | 11 / 21.2% (52) |
| Strong 470 (by detection sites) | 213 / 45.3% | – | 19 / 55.9% (34) | 124 / 50.0% (248) | 61 / 36.7% (166) | 9 / 40.9% (22) | none strong |

## S8.5 Reading

On taxa that exist under both labellings, the labelling made no detectable
difference to how well maps predicted later finds, even with DNA as the truth.
By the registered rule, C3 therefore rests on coverage: half the modelled taxa
and 45% of those with a strong map carry only a provisional name and exist as
distinct taxa only under DNA labels. A comparison with morphology-named records
outside MycoMap's validated set (GBIF, E6c) has not been run.

## S8.6 Cost

E9's fits at most about USD 25 at list price (DNA at most 13; record at most 12
so far, final figure pending; the registry's own estimate is about 6.8);
scoring about 0.53; the comparison about 0.05 (`costs.md`).
