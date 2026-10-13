# Appendix S1, Section S3: predictors and their selection (draft)

*Moved from the main text on 2026-10-13 (lean main text); edited only for the move.*

## S3.1 Grid and layers

Everything is modelled on a North America Albers Equal Area Conic grid with
5 km cells (3.7 million cells); the frozen release is on this grid. The
pipeline also defines a nested 1 km grid, which no release used here.

Sixty-nine predictor bands in eight layers (Appendix S1: Section S3): 19 WorldClim 2.1
bioclimatic variables (1970–2000) and elevation (Fick & Hijmans 2017); slope
and roughness derived on the grid; topsoil (0–5 cm) pH, organic carbon, total
nitrogen, clay, sand and cation exchange capacity from SoilGrids 2.0 (Poggio
et al. 2021); six land-cover fractions from ESA WorldCover (Zanaga et al.
2021); the share of a cell's trees in each of 29 host genera (19 mainly
mycorrhizal hosts plus the conifer share, and 10 genera hosting decay and
parasitic fungi: maple, ash, elm, juniper, cedar, tulip tree, cherry,
sweetgum, sycamore, black locust), from BIGMAP in the United States (USDA
Forest Service FIA, n.d.; Wilson et al. 2018) and the Canadian National
Forest Inventory kNN maps (Beaudoin et al. 2014), with a flag where neither
inventory reaches (Alaska, Hawaii, Puerto Rico, Mexico); and needleleaf,
broadleaf and mixed forest shares from NALCMS (CEC 2023), filled from
Copernicus Global Land Cover (Buchhorn et al. 2020) on Hawaii and the
Caribbean, with a flag. The tree models also take log collecting effort;
Maxent does not. [CHECK: the frozen release's layer manifest (sha256) once
the rebuild finishes; the count above is from the rebuild lane's copy.]

Sources are cropped, reprojected and averaged onto the grid (never
interpolated); land cells left empty are filled from neighbours within
10 km. Candidate layers (water balance, bedrock, landform, ClimateNA
1991–2020 normals, single tree species) were built and tested in paired
layer sweeps and not adopted (Appendix S1: Section S3; E8).

## S3.2 Predictor selection

For Maxent and the small-model ensembles, predictors correlated at |r| ≥ 0.7
on non-detection sites are pruned, keeping the earlier one in a fixed
ecological order (soil pH first; host trees second for ectomycorrhizal genera
per FungalTraits, Põlme et al. 2020), with an allowance for host-tree bands
and a cap of one predictor per four detection sites (set by a 153-taxon sweep
[pre-freeze]). The tree models receive all predictors.

## S3.3 Layer sweeps and variable importance

[PENDING E8: importance by guild from the frozen release; the layer sweeps of 2026-09-30, 10-06 and 10-08.]
