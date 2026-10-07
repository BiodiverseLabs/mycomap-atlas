import type { ReactNode } from "react";

/**
 * What each dataset in "What drives this map" is, which of its variables the
 * models are offered, and why. Keyed by layer id. Every production layer
 * needs an entry (tests/testthat/test-sources.R checks), and a change to a
 * layer in R/layers.R should change its note here.
 */
export const LAYER_NOTES: Record<string, ReactNode> = {
  bioclim: (
    <>
      All 19 WorldClim bioclimatic variables (1970–2000 averages): temperature and rainfall
      means, their seasons and their extremes. Many are near-copies of each other, so Maxent keeps
      one of each closely related pair, moisture before temperature; the forest and boosted trees
      are offered all 19.
    </>
  ),
  elevation: <>Height above sea level (WorldClim, from SRTM), averaged over each 5 km cell.</>,
  terrain: (
    <>
      Slope and terrain roughness, worked out from the elevation layer. Aspect, wetness and heat
      load were tested and made no difference to the maps, so they are left out.
    </>
  ),
  soil: (
    <>
      Six properties of the topsoil (0–5 cm) from SoilGrids 2.0: pH, organic carbon, total
      nitrogen, clay, sand and cation exchange capacity. Silt is left out because sand, silt and
      clay add up to the whole. Soil pH comes first of all the variables Maxent is offered: it is
      among the strongest known drivers of where fungi grow. pH deeper down (15–30 cm), bulk
      density and stoniness were tested and did not improve the maps.
    </>
  ),
  landcover: (
    <>
      How much of each cell is trees, shrubs, grassland, wetland, open water and built-up land
      (ESA WorldCover 2021). Tree cover says how much forest there is, not which trees: forest
      type and host trees say that.
    </>
  ),
  foresttype: (
    <>
      How much of each cell is needleleaf, broadleaf and mixed forest, counted from 30 m pixels
      of the North American land cover map (NALCMS 2020). Its six forest classes are grouped into
      three: boreal taiga counts as needleleaf, and evergreen and deciduous broadleaf are one
      group, since the difference matters only in Mexico. Mixed forest stays a group of its own
      because mycologists treat mixed wood as a habitat, not as half of each. Hawaii and the
      Caribbean come from Copernicus land cover.
    </>
  ),
  hosts: (
    <>
      Each tree genus's share of the trees in a cell, from the US Forest Service's BIGMAP (327
      species) and Canada's National Forest Inventory, plus the share that are conifers. The 19
      genera are the main partners of North America's mycorrhizal fungi — pine, oak, spruce, fir,
      Douglas fir, hemlock, birch, poplar, beech, larch and others — with the species of each
      genus added together. For mycorrhizal fungi they come right after soil pH in Maxent's
      order. Alaska, Hawaii, Mexico and Puerto Rico are outside both inventories; there the
      models are told the trees are unknown rather than absent.
    </>
  ),
  hostsdecay: (
    <>
      The share of a cell's trees in each of 16 more genera: maple, ash, elm, juniper and eastern
      redcedar, northern white-cedar and western redcedar, tulip tree, cherry and plum, sweetgum,
      sycamore, black locust, walnut and butternut, hackberry, bald cypress, coast redwood, giant
      sequoia and incense-cedar. Maple, ash and elm host mycorrhizal, wood-decay and parasitic
      fungi alike, so these are host trees like the 19 genera, shown and measured with them. Same
      sources and same measure (BIGMAP in the lower 48, Canada's National Forest Inventory), as
      shares of the same total of trees. Canada's inventory maps maple, ash, elm, juniper, cedar,
      cherry and walnut; the others read 0 there. Measured on 158 taxa (30 September 2026), the
      first ten raised held-out AUC by 0.0018 ± 0.0013 overall and by 0.004 for species with
      30–49 collecting sites, maple doing most of the work. Elm keeps a place in any model of a
      region where it is at least 1% of the trees; the rest count toward the same allowance of
      trees as the host genera.
    </>
  ),
  hostspecies: (
    <>
      The share of a cell's trees that are each tree species: 316 species, every one BIGMAP maps
      (trees named only to genus aside), with a variety or subspecies that FIA codes separately
      kept apart, so black cottonwood is not balsam poplar. A genus can hide what a fungus
      follows: of 48 oaks, some run from the middle of the continent south and others north.
      Same sources and measure as the genus bands; Canada's inventory maps 60 of these species,
      and the rest read 0 there. A model draws on the species of its own region, by share,
      within the same allowance of trees.
    </>
  ),
  waterbalance: (
    <>
      Moisture deficit, autumn climate, snow, humidity, evapotranspiration and vapour pressure
      deficit (ClimateNA and TerraClimate). Tested twice against the maps without it and it made
      no difference, so production models are not offered it.
    </>
  ),
};
