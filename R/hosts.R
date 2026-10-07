# Host trees.
#
# An ectomycorrhizal fungus lives on the roots of particular trees, so where
# it can grow is bounded by where its hosts grow. Tree cover as a fraction
# (the landcover layer) cannot say that: a spruce bog and an oak ridge are
# both "trees". This layer says which trees.
#
# No single product maps tree species across the continent, but the two
# national forest inventories each do so for their own country:
#
#   United States  USFS FIA BIGMAP 2018: aboveground biomass per species,
#                  30 m, the lower 48 only. Read from its ArcGIS ImageServer
#                  one species at a time, rather than downloading 400+ GB of
#                  zips.
#   Canada         NFI kNN 2011: percent composition per species, 250 m.
#
# They measure different things, so both are brought to one unit: the SHARE
# of a cell's trees that belong to a genus, 0 to 1. In BIGMAP that is genus
# biomass over the biomass of all its species; in NFI it is the genus's summed
# percentages over the needleleaf and broadleaf groups together. A cell with
# no trees has a share of 0 for every genus, not a missing value. Alaska,
# Hawaii, Puerto Rico
# and Mexico are in neither inventory and are left empty (NA): about 2.5% of
# the records, which drop out of fitting and are not mapped.

# One band per host genus, in the order they are offered to Maxent's
# predictor pruning (R/predictors.R). Conifer share comes first: for many
# ectomycorrhizal fungi the first split is conifer against broadleaf, and when
# the cap on predictors binds one band that says it is worth more than one
# genus. The genera follow roughly by how many North American ectomycorrhizal
# fungi they host. Corylus is left out: BIGMAP has no layer for it.
ATLAS_HOST_GENERA <- c(
  "Pinus", "Quercus", "Picea", "Abies", "Pseudotsuga", "Tsuga", "Betula",
  "Populus", "Fagus", "Larix", "Castanea", "Notholithocarpus", "Carya",
  "Alnus", "Salix", "Tilia", "Carpinus", "Ostrya", "Arbutus"
)

ATLAS_HOST_BANDS <- c("host_conifer", paste0("host_", tolower(ATLAS_HOST_GENERA)))

ATLAS_BIGMAP_URL <- paste0(
  "https://imagery.geoplatform.gov/iipp/rest/services/Vegetation/",
  "USFS_FIA_BIGMAP_AboveGroundBiomass/ImageServer"
)
ATLAS_NFI_URL <- paste0(
  "https://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/",
  "canada-forests-attributes_attributs-forests-canada/2011-attributes_attributs-2011"
)
# United States Census cartographic boundaries, 1:500,000. BIGMAP's export
# fills everything outside its data with 0, exactly as it fills a treeless
# field, so "inside the lower 48" has to come from a boundary.
ATLAS_CONUS_URL <- "https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_500k.zip"

# States and territories BIGMAP does not cover.
ATLAS_NOT_CONUS <- c("AK", "HI", "PR", "VI", "GU", "MP", "AS")

ATLAS_BIGMAP_TOTAL <- "SPCD_0000_Total"

# BIGMAP still files tanoak under its old genus.
ATLAS_BIGMAP_ALIASES <- c(Lithocarpus = "Notholithocarpus")

# NFI's four-letter genus codes, for the host genera it has. It has no
# Castanea (American chestnut barely reaches Ontario, and is all but gone) and
# no Notholithocarpus (not Canadian); those shares are 0 in Canada.
ATLAS_NFI_GENERA <- c(
  Pinu = "Pinus", Quer = "Quercus", Pice = "Picea", Abie = "Abies",
  Pseu = "Pseudotsuga", Tsug = "Tsuga", Betu = "Betula", Popu = "Populus",
  Fagu = "Fagus", Lari = "Larix", Cary = "Carya", Alnu = "Alnus",
  Sali = "Salix", Tili = "Tilia", Carp = "Carpinus", Ostr = "Ostrya",
  Arbu = "Arbutus"
)

# More host genera (R/layers.R, hostsdecay): the trees the ectomycorrhizal
# partners above leave out. Maple, ash and elm are hosts of mycorrhizal, decay
# and parasitic fungi alike (Steve, 2026-10-06), so the layer is shown as host
# trees with the others, not as "decay hosts"; its id stays hostsdecay so
# built layers and stored models keep their names. Each is a share of the same
# trees the host layer's genera are shares of — its totals are read from the
# host layer's cache, not summed again — so the two layers' bands are parts of
# one whole. BIGMAP has all sixteen. NFI maps seven; the others barely reach
# Canada, or not at all, and are 0 there.
ATLAS_DECAY_HOST_GENERA <- c(
  "Acer", "Fraxinus", "Ulmus", "Juniperus", "Thuja", "Liriodendron", "Prunus",
  "Liquidambar", "Platanus", "Robinia", "Juglans", "Celtis", "Taxodium",
  "Sequoia", "Sequoiadendron", "Calocedrus"
)

ATLAS_HOST_DECAY_BANDS <- paste0("host_", tolower(ATLAS_DECAY_HOST_GENERA))

ATLAS_NFI_DECAY_GENERA <- c(
  Acer = "Acer", Frax = "Fraxinus", Ulmu = "Ulmus", Juni = "Juniperus",
  Thuj = "Thuja", Prun = "Prunus", Jugl = "Juglans"
)

# ---- tree species ----------------------------------------------------------
#
# A genus can hide what a fungus follows: of 48 oaks BIGMAP maps, some run
# from the middle of the continent south and others from the middle north
# (Steve, 2026-10-06). The species layer (hostspecies) has one band per tree
# species, as a share of the same trees the genus bands are shares of. FIA's
# species codes name them: BIGMAP's raster functions carry the code, and
# inst/extdata/fia-tree-species.csv (from FIA's REF_SPECIES, public domain)
# gives each code's scientific and common name. A variety or subspecies with
# its own code keeps its own band: black cottonwood is not balsam poplar.

#' Where FIA's species table lives: the source tree when running from it (as
#' batch workers in a checkout do, sourcing R/ without the package), the
#' installed package otherwise.
atlas_tree_species_path <- function(root = Sys.getenv("ATLAS_ROOT", unset = ".")) {
  source <- file.path(root, "inst", "extdata", "fia-tree-species.csv")
  if (file.exists(source)) {
    return(source)
  }
  system.file("extdata", "fia-tree-species.csv", package = "mycomapatlas")
}

#' BIGMAP's tree species with FIA's names: spcd, genus, scientific_name,
#' common_name, softwood.
atlas_tree_species <- local({
  table <- NULL
  function() {
    if (is.null(table)) {
      path <- atlas_tree_species_path()
      if (!nzchar(path) || !file.exists(path)) {
        stop("FIA's tree species table (inst/extdata/fia-tree-species.csv) is missing", call. = FALSE)
      }
      table <<- utils::read.csv(path, stringsAsFactors = FALSE, encoding = "UTF-8")
    }
    table
  }
})

#' The band a tree species is published as: host_<genus>_<epithet>, with a
#' variety's or subspecies' name after it (host_populus_balsamifera_trichocarpa).
atlas_species_band <- function(scientific_name) {
  x <- tolower(scientific_name)
  x <- gsub("\\b(var|ssp|subsp)[.]", " ", x)
  x <- gsub("[^a-z]+", "_", trimws(x))
  paste0("host_", gsub("^_+|_+$", "", x))
}

#' A species band's name for people: "Northern red oak (Quercus rubra)".
atlas_species_label <- function(common_name, scientific_name) {
  common <- paste0(toupper(substr(common_name, 1L, 1L)), substring(common_name, 2L))
  paste0(common, " (", scientific_name, ")")
}

# Canada's NFI species files, by FIA species code. NFI names a file by four
# letters of the genus and three of the epithet; where three letters are
# ambiguous the file is matched by hand: Acer_Sac is sugar maple and Acer_Sah
# silver maple, Pinu_Mon western white pine, Pinu_Str eastern white pine,
# Popu_Tri black cottonwood (FIA's Populus balsamifera ssp. trichocarpa),
# Abie_Las subalpine fir (corkbark fir does not reach Canada). A species NFI
# does not map reads 0 in Canada; the trees of its genus NFI could not name
# (the _Spp files) count toward the genus bands only.
ATLAS_NFI_SPECIES <- c(
  Abie_Ama = 11L, Abie_Bal = 12L, Abie_Las = 19L, Acer_Mac = 312L, Acer_Neg = 313L,
  Acer_Pen = 315L, Acer_Rub = 316L, Acer_Sah = 317L, Acer_Sac = 318L, Acer_Spi = 319L,
  Alnu_Rub = 351L, Arbu_Men = 361L, Betu_All = 371L, Betu_Pap = 375L, Betu_Pop = 379L,
  Carp_Car = 391L, Cary_Cor = 402L, Cham_Noo = 42L, Fagu_Gra = 531L, Frax_Ame = 541L,
  Frax_Nig = 543L, Frax_Pen = 544L, Jugl_Cin = 601L, Jugl_Nig = 602L, Juni_Vir = 68L,
  Lari_Lar = 71L, Lari_Lya = 72L, Lari_Occ = 73L, Ostr_Vir = 701L, Pice_Abi = 91L,
  Pice_Eng = 93L, Pice_Gla = 94L, Pice_Mar = 95L, Pice_Rub = 97L, Pice_Sit = 98L,
  Pinu_Alb = 101L, Pinu_Ban = 105L, Pinu_Con = 108L, Pinu_Mon = 119L, Pinu_Pon = 122L,
  Pinu_Res = 125L, Pinu_Str = 129L, Pinu_Syl = 130L, Popu_Bal = 741L, Popu_Gra = 743L,
  Popu_Tre = 746L, Popu_Tri = 747L, Prun_Pen = 761L, Prun_Ser = 762L, Pseu_Men = 202L,
  Quer_Alb = 802L, Quer_Mac = 823L, Quer_Rub = 833L, Sorb_Ame = 935L, Thuj_Occ = 241L,
  Thuj_Pli = 242L, Tili_Ame = 951L, Tsug_Can = 261L, Tsug_Het = 263L, Tsug_Mer = 264L
)

# The species the species layer carries, by FIA code: every BIGMAP species
# but the "spp." catch-alls (trees FIA could not name past the genus), written
# out so the package needs no file to load. See atlas_host_species_bands for
# their band names; a test checks the list against the species table.
ATLAS_HOST_SPECIES <- c(
  11L, 12L, 15L, 16L, 17L, 18L, 19L, 20L, 21L, 22L, 41L, 42L, 43L, 51L, 52L, 55L, 56L,
  58L, 59L, 61L, 62L, 63L, 64L, 65L, 66L, 67L, 68L, 69L, 71L, 72L, 73L, 81L, 91L, 92L,
  93L, 94L, 95L, 96L, 97L, 98L, 101L, 102L, 103L, 104L, 105L, 106L, 107L, 108L, 109L,
  110L, 111L, 113L, 114L, 115L, 116L, 117L, 118L, 119L, 120L, 121L, 122L, 123L, 125L,
  126L, 127L, 128L, 129L, 130L, 131L, 132L, 133L, 134L, 136L, 137L, 140L, 141L, 142L,
  143L, 201L, 202L, 211L, 212L, 221L, 222L, 231L, 241L, 242L, 251L, 261L, 262L, 263L,
  264L, 303L, 311L, 312L, 313L, 314L, 315L, 316L, 317L, 318L, 319L, 320L, 322L, 323L,
  331L, 332L, 333L, 334L, 341L, 345L, 351L, 352L, 361L, 363L, 367L, 371L, 372L, 373L,
  374L, 375L, 379L, 381L, 391L, 401L, 402L, 403L, 404L, 405L, 407L, 408L, 409L, 410L,
  411L, 412L, 413L, 421L, 422L, 423L, 431L, 451L, 452L, 461L, 462L, 463L, 471L, 475L,
  481L, 491L, 492L, 501L, 502L, 513L, 521L, 522L, 523L, 531L, 541L, 542L, 543L, 544L,
  545L, 546L, 547L, 548L, 549L, 551L, 552L, 555L, 571L, 581L, 582L, 591L, 601L, 602L,
  604L, 605L, 606L, 611L, 621L, 631L, 641L, 651L, 652L, 653L, 654L, 655L, 658L, 661L,
  662L, 663L, 681L, 682L, 683L, 691L, 692L, 693L, 694L, 701L, 711L, 712L, 721L, 722L,
  730L, 731L, 741L, 742L, 743L, 744L, 745L, 746L, 747L, 748L, 749L, 756L, 757L, 761L,
  762L, 763L, 766L, 768L, 771L, 772L, 801L, 802L, 803L, 804L, 805L, 806L, 807L, 808L,
  809L, 810L, 811L, 812L, 813L, 814L, 815L, 816L, 817L, 818L, 819L, 820L, 821L, 822L,
  823L, 824L, 825L, 826L, 827L, 828L, 829L, 830L, 831L, 832L, 833L, 834L, 835L, 836L,
  837L, 838L, 839L, 840L, 841L, 842L, 843L, 846L, 847L, 851L, 853L, 854L, 857L, 858L,
  863L, 867L, 868L, 870L, 873L, 876L, 882L, 886L, 901L, 912L, 919L, 921L, 922L, 923L,
  925L, 927L, 931L, 935L, 937L, 940L, 951L, 952L, 953L, 971L, 972L, 973L, 974L, 975L,
  977L, 981L, 986L, 987L, 988L, 989L, 992L, 993L, 994L, 995L, 996L, 997L, 999L, 8513L,
  8514L
)

#' The species layer's bands, one per species in `spcd`, in that order.
atlas_host_species_bands <- function(spcd = ATLAS_HOST_SPECIES, species = atlas_tree_species()) {
  atlas_species_band(species$scientific_name[match(spcd, species$spcd)])
}

#' Labels for the species bands, named by band.
atlas_host_species_labels <- function(spcd = ATLAS_HOST_SPECIES, species = atlas_tree_species()) {
  rows <- species[match(spcd, species$spcd), , drop = FALSE]
  stats::setNames(atlas_species_label(rows$common_name, rows$scientific_name),
                  atlas_species_band(rows$scientific_name))
}

#' A set of host genera (or species), and the files it keeps under raw/hosts.
#'
#' "hosts" is the production layer: it reads every BIGMAP species and both NFI
#' groups, because its sums carry the tree total and the conifer band. A
#' second set ("hostsdecay") reads only its own genera and takes the total
#' from production's cache, so its cache files and its species folder must
#' never be production's: atlas_bigmap_sums deletes its species folder once it
#' has summed, and a second set that shared a name would delete or overwrite
#' what production built.
atlas_host_set <- function(id = "hosts", sets = atlas_host_sets()) {
  if (!is.character(id) || length(id) != 1L || !id %in% names(sets)) {
    stop("unknown host set: ", id, call. = FALSE)
  }
  set <- sets[[id]]
  files <- atlas_host_set_files(set)
  # Plain names under raw/hosts: an empty one would make the species folder
  # raw/hosts itself, and atlas_bigmap_sums deletes that folder.
  plain <- nzchar(files) & !grepl("/", files, fixed = TRUE) &
    !grepl("\\", files, fixed = TRUE) & !grepl("^[.]+$", files)
  if (length(files) != 4L || !all(plain)) {
    stop("host set ", id, " must name its four files plainly", call. = FALSE)
  }
  if (!isTRUE(set$totals)) {
    clash <- intersect(atlas_host_set_files(set), atlas_host_set_files(sets$hosts))
    if (length(clash)) {
      stop("host set ", id, " would share production's files: ", paste(clash, collapse = ", "),
           call. = FALSE)
    }
  }
  set
}

#' Every host set, by id (atlas_host_set).
atlas_host_sets <- function() {
  list(
    hosts = list(
      id = "hosts", genera = ATLAS_HOST_GENERA, nfi_codes = ATLAS_NFI_GENERA,
      totals = TRUE, bigmap = "bigmap-1km.tif", species_dir = "bigmap-species",
      nfi = "nfi-1km.tif", nfi_dir = "nfi"
    ),
    hostsdecay = list(
      id = "hostsdecay", genera = ATLAS_DECAY_HOST_GENERA, nfi_codes = ATLAS_NFI_DECAY_GENERA,
      totals = FALSE, bigmap = "bigmap-decay-1km.tif", species_dir = "bigmap-species-decay",
      nfi = "nfi-decay-1km.tif", nfi_dir = "nfi-decay"
    ),
    # One band per tree species (ATLAS_HOST_SPECIES), not per genus. Its
    # species files are kept: there are 300 of them, read one at a time from
    # BIGMAP over hours, and a later choice of species should not mean
    # reading them all again.
    hostspecies = list(
      id = "hostspecies", genera = character(), species = ATLAS_HOST_SPECIES,
      nfi_codes = character(), nfi_species = ATLAS_NFI_SPECIES,
      totals = FALSE, keep_species = TRUE, bigmap = "bigmap-species-1km.tif",
      species_dir = "bigmap-species-all", nfi = "nfi-species-1km.tif", nfi_dir = "nfi-species"
    )
  )
}

#' The file and folder names a host set writes under raw/hosts.
atlas_host_set_files <- function(set) {
  unlist(set[c("bigmap", "species_dir", "nfi", "nfi_dir")], use.names = FALSE)
}

#' The parts a host set sums its trees into, as named in its sums: one per
#' genus (lower case), or one per species (the band name without host_).
atlas_host_set_parts <- function(set) {
  if (length(set[["species"]])) {
    sub("^host_", "", atlas_host_species_bands(set[["species"]]))
  } else {
    tolower(set$genera)
  }
}

#' The bands a host set's layer has: the conifer share when it carries the
#' totals, then one share per genus or species.
atlas_host_set_bands <- function(set) {
  c(if (isTRUE(set$totals)) "host_conifer", paste0("host_", atlas_host_set_parts(set)))
}

# How BIGMAP is sampled. Its server cannot block-average: asked for a coarse
# pixel, it reads one point, and its "average" resampling (ResamplingType 7)
# turned out to be point samples too, shifted by a row. Measured over a
# 50 km square of the Oregon Cascades against the 30 m truth, 1 km cells built
# from 250 m point samples correlate at 0.985 with the true block means, and
# 5 km cells at 0.999; one point per cell manages 0.43. So BIGMAP is read at
# 250 m and averaged here, and the same read serves both grids: 250 m nests in
# 1 km, which nests in 5 km.
ATLAS_BIGMAP_SAMPLE_M <- 250
ATLAS_BIGMAP_TILE_PX <- 8000

# Both inventories are summed onto 1 km cells once; each grid is built from
# those sums.
ATLAS_HOST_BASE_M <- 1000

# The grid's projection (ATLAS_CRS) in the ESRI form the ImageServer accepts,
# so BIGMAP is drawn straight onto the grid's own cells.
ATLAS_ESRI_WKT <- paste0(
  'PROJCS["MycoMap_Atlas_Albers",GEOGCS["GCS_North_American_1983",',
  'DATUM["D_North_American_1983",SPHEROID["GRS_1980",6378137.0,298.257222101]],',
  'PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],',
  'PROJECTION["Albers"],PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],',
  'PARAMETER["Central_Meridian",-96.0],PARAMETER["Standard_Parallel_1",20.0],',
  'PARAMETER["Standard_Parallel_2",60.0],PARAMETER["Latitude_Of_Origin",40.0],',
  'UNIT["Meter",1.0]]'
)

# ---- the arithmetic, on plain vectors or rasters --------------------------

#' The share of a cell's trees that a part of them makes up.
#'
#' Where there are no trees the share is 0, not missing: a prairie is a place
#' with no spruce, which is information. Missing stays missing. Shares are
#' clamped to 0-1, because a genus sampled at 250 m can overshoot a total
#' sampled at the same points by rounding.
atlas_host_share <- function(part, total) {
  if (inherits(part, "SpatRaster")) {
    share <- terra::ifel(total > 0, part / total, 0)
    return(terra::clamp(share, 0, 1, values = TRUE))
  }
  share <- ifelse(total > 0, part / total, 0)
  pmin(pmax(share, 0), 1)
}

#' Shares from a stack of sums: a "total" band, and one band per part.
#'
#' The part bands come back as host_<name>, in the order they were given.
atlas_host_shares <- function(sums) {
  if (!"total" %in% names(sums)) {
    stop("host sums need a total band", call. = FALSE)
  }
  parts <- setdiff(names(sums), "total")
  out <- lapply(parts, function(p) atlas_host_share(sums[[p]], sums[["total"]]))
  names(out) <- paste0("host_", parts)
  if (inherits(sums, "SpatRaster")) {
    out <- terra::rast(out)
    names(out) <- paste0("host_", parts)
  }
  out
}

#' Sum members into groups. `values` is a named list (vectors or rasters),
#' `groups` a named list of member names per group. A group with no members is
#' 0 wherever the values are defined, which is what a genus absent from an
#' inventory means.
atlas_group_sums <- function(values, groups) {
  missing <- setdiff(unlist(groups, use.names = FALSE), names(values))
  if (length(missing)) {
    stop("no values for: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  zero <- values[[1]] * 0
  lapply(groups, function(members) {
    if (!length(members)) return(zero)
    Reduce(`+`, values[members])
  })
}

#' Keep a layer's values inside the region an inventory covers and nothing
#' outside it. Inside, missing means the inventory found no trees, so it
#' becomes 0; outside, the inventory says nothing, so everything is NA.
atlas_inventory_fill <- function(x, inside) {
  if (inherits(x, "SpatRaster")) {
    filled <- terra::ifel(is.na(x), 0, x)
    return(terra::mask(filled, inside, maskvalues = c(0, NA), updatevalue = NA))
  }
  inside <- !is.na(inside) & as.logical(inside)
  ifelse(inside, ifelse(is.na(x), 0, x), NA_real_)
}

#' One layer from the two inventories.
#'
#' Where only one reaches a cell, it is used. Where both do — along the
#' border, where a cell straddles it — the cell goes to the country its centre
#' lies in (`us_first`), so a cell that is mostly Canadian forest is not
#' described by the sliver of American field that also touches it.
atlas_mosaic_hosts <- function(us, canada, us_first) {
  if (inherits(us, "SpatRaster")) {
    pick <- !is.na(us[[1]]) & (us_first | is.na(canada[[1]]))
    out <- lapply(seq_len(terra::nlyr(us)), function(i) terra::ifel(pick, us[[i]], canada[[i]]))
    out <- terra::rast(out)
    names(out) <- names(us)
    return(out)
  }
  us_first <- !is.na(us_first) & as.logical(us_first)
  ifelse(!is.na(us) & (us_first | is.na(canada)), us, canada)
}

#' Round a window outward to whole steps of the grid, so every grid's cells
#' nest in it. Named like ATLAS_GRID_EXTENT.
atlas_snap_window <- function(xmin, xmax, ymin, ymax, step = 5000) {
  c(
    xmin = max(floor(xmin / step) * step, ATLAS_GRID_EXTENT[["xmin"]]),
    xmax = min(ceiling(xmax / step) * step, ATLAS_GRID_EXTENT[["xmax"]]),
    ymin = max(floor(ymin / step) * step, ATLAS_GRID_EXTENT[["ymin"]]),
    ymax = min(ceiling(ymax / step) * step, ATLAS_GRID_EXTENT[["ymax"]])
  )
}

# ---- BIGMAP --------------------------------------------------------------

#' What each BIGMAP raster function holds: species code, genus, and whether it
#' counts toward a host band or the conifer band.
#'
#' Names look like SPCD_0202_Pseudotsuga_menziesii. FIA species codes below
#' 300 are the softwoods, which is what conifer means here. The total and
#' anything that is not a species are left out.
atlas_bigmap_species <- function(functions, genera = ATLAS_HOST_GENERA) {
  functions <- as.character(functions)
  pattern <- "^SPCD_([0-9]{4})_([A-Za-z]+)_.*$"
  functions <- functions[grepl(pattern, functions) & functions != ATLAS_BIGMAP_TOTAL]
  spcd <- as.integer(sub(pattern, "\\1", functions))
  genus <- sub(pattern, "\\2", functions)
  aliased <- ATLAS_BIGMAP_ALIASES[genus]
  genus[!is.na(aliased)] <- aliased[!is.na(aliased)]
  data.frame(
    fn = functions,
    spcd = spcd,
    genus = unname(genus),
    host = genus %in% genera,
    conifer = spcd >= 1L & spcd < 300L,
    stringsAsFactors = FALSE
  )
}

#' The raster functions to read: every species, because every species is part
#' of the total a share is taken over. A set whose total comes from the
#' production cache names its genera, and only their species are read.
atlas_bigmap_needed <- function(species, genera = NULL) {
  if (is.null(genera)) species$fn else species$fn[species$genus %in% genera]
}

#' Which raster functions go into each band of the sums.
#'
#' The total is the sum of every species, not BIGMAP's own SPCD_0000_Total.
#' That total is modelled separately from the species and does not add up to
#' them: over 2,500 of its 30 m pixels in the Oregon Cascades the species
#' summed to 0.85 of it, correlating at only 0.80 pixel by pixel. Shares over
#' it would run about 15% low and a genus's share would not be its part of the
#' same whole the other genera are parts of. Summing the species also matches
#' NFI, whose percentages are shares of the species it identifies.
atlas_bigmap_groups <- function(species, genera = ATLAS_HOST_GENERA, totals = TRUE,
                                spcd = NULL) {
  groups <- if (isTRUE(totals)) {
    list(total = species$fn, conifer = species$fn[species$conifer])
  } else {
    list()
  }
  for (genus in genera) {
    groups[[tolower(genus)]] <- species$fn[species$genus == genus]
  }
  # A species band is its own code's layer: a variety with a code of its own
  # is a band of its own, never folded into its species.
  if (length(spcd)) {
    parts <- sub("^host_", "", atlas_host_species_bands(spcd))
    for (i in seq_along(spcd)) {
      groups[[parts[[i]]]] <- species$fn[species$spcd == spcd[[i]]]
    }
  }
  groups
}

#' The exportImage request for one species over one tile of the grid.
#'
#' bbox is c(xmin, ymin, xmax, ymax) in grid metres and size c(width, height)
#' in pixels. Nearest-neighbour reads real 30 m pixels at the sample points;
#' the averaging is done here (see ATLAS_BIGMAP_SAMPLE_M).
atlas_bigmap_export_url <- function(fn, bbox, size, base = ATLAS_BIGMAP_URL) {
  sr <- as.character(jsonlite::toJSON(list(wkt = ATLAS_ESRI_WKT), auto_unbox = TRUE))
  query <- c(
    bbox = paste(sprintf("%.0f", bbox), collapse = ","),
    bboxSR = sr,
    imageSR = sr,
    size = paste(sprintf("%.0f", size), collapse = ","),
    format = "tiff",
    pixelType = "F32",
    interpolation = "RSP_NearestNeighbor",
    compression = "LZ77",
    renderingRule = as.character(jsonlite::toJSON(list(rasterFunction = fn), auto_unbox = TRUE)),
    f = "image"
  )
  encoded <- vapply(query, utils::URLencode, character(1), reserved = TRUE)
  paste0(base, "/exportImage?", paste(names(query), encoded, sep = "=", collapse = "&"))
}

#' Split a window into tiles of at most tile_px pixels a side, from the top
#' left, each a whole number of sample pixels.
atlas_bigmap_tiles <- function(window, sample_m = ATLAS_BIGMAP_SAMPLE_M,
                               tile_px = ATLAS_BIGMAP_TILE_PX) {
  width <- tile_px * sample_m
  if ((window[["xmax"]] - window[["xmin"]]) %% sample_m ||
      (window[["ymax"]] - window[["ymin"]]) %% sample_m) {
    stop("the window is not a whole number of ", sample_m, " m pixels", call. = FALSE)
  }
  tiles <- list()
  for (y1 in seq(window[["ymax"]], window[["ymin"]] + 1, by = -width)) {
    for (x0 in seq(window[["xmin"]], window[["xmax"]] - 1, by = width)) {
      x1 <- min(x0 + width, window[["xmax"]])
      y0 <- max(y1 - width, window[["ymin"]])
      tiles[[length(tiles) + 1L]] <- list(
        bbox = c(xmin = x0, ymin = y0, xmax = x1, ymax = y1),
        size = c((x1 - x0) / sample_m, (y1 - y0) / sample_m)
      )
    }
  }
  tiles
}

#' The raster functions BIGMAP offers, from the service's own description.
atlas_bigmap_functions <- function(http = atlas_host_http, base = ATLAS_BIGMAP_URL) {
  dest <- tempfile(fileext = ".json")
  on.exit(unlink(dest), add = TRUE)
  atlas_fetch_file(paste0(base, "?f=json"), dest, http = http)
  info <- jsonlite::fromJSON(dest, simplifyVector = FALSE)
  vapply(info$rasterFunctionInfos %||% list(), function(x) as.character(x$name), character(1))
}

#' One species' mean biomass on 1 km cells across the window, read from BIGMAP
#' tile by tile at 250 m and averaged. Written to dir and reused on the next
#' run, so an interrupted build picks up where it stopped.
atlas_bigmap_fetch_species <- function(fn, window, dir, http = atlas_host_http, quiet = FALSE) {
  out <- file.path(dir, paste0(fn, ".tif"))
  if (file.exists(out)) {
    return(invisible(list(path = out, bytes = 0)))
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  fact <- ATLAS_HOST_BASE_M / ATLAS_BIGMAP_SAMPLE_M
  tiles <- atlas_bigmap_tiles(window)
  bytes <- 0
  parts <- lapply(seq_along(tiles), function(i) {
    tile <- tiles[[i]]
    part <- file.path(dir, paste0(fn, "-tile", i, ".tif"))
    on.exit(unlink(part), add = TRUE)
    atlas_fetch_file(atlas_bigmap_export_url(fn, tile$bbox, tile$size), part,
                     http = http, check = atlas_is_tiff)
    bytes <<- bytes + file.info(part)$size
    sampled <- terra::rast(part)
    if (terra::ncol(sampled) != tile$size[[1]] || terra::nrow(sampled) != tile$size[[2]]) {
      stop("BIGMAP returned ", terra::ncol(sampled), " x ", terra::nrow(sampled), " for ", fn,
           ", not the ", tile$size[[1]], " x ", tile$size[[2]], " asked for", call. = FALSE)
    }
    # Placed where it was asked for, rather than trusting the file's own
    # georeferencing to the metre.
    terra::ext(sampled) <- terra::ext(tile$bbox[["xmin"]], tile$bbox[["xmax"]],
                                      tile$bbox[["ymin"]], tile$bbox[["ymax"]])
    terra::crs(sampled) <- ATLAS_CRS
    terra::toMemory(terra::aggregate(sampled, fact, fun = "mean"))
  })
  merged <- if (length(parts) == 1L) parts[[1]] else terra::merge(terra::sprc(parts))
  names(merged) <- fn
  atlas_write_raster_whole(merged, out)
  if (!quiet) message("    ", fn, ": ", round(bytes / 1e6, 1), " MB")
  invisible(list(path = out, bytes = bytes))
}

#' BIGMAP summed into bands on 1 km cells: the biomass of every species,
#' of the conifers, and of each host genus. The species files are removed once
#' summed.
#'
#' A second set (atlas_host_set) sums only its own genera, into its own
#' cache file, from its own species folder.
atlas_bigmap_sums <- function(dir, window, http = atlas_host_http, quiet = FALSE,
                              functions = NULL, keep_species = FALSE,
                              set = atlas_host_set("hosts")) {
  out <- file.path(dir, set$bigmap)
  if (file.exists(out)) {
    return(terra::rast(out))
  }
  functions <- functions %||% atlas_bigmap_functions(http)
  species <- atlas_bigmap_species(functions, set$genera)
  needed <- if (length(set[["species"]])) {
    species$fn[species$spcd %in% set[["species"]]]
  } else {
    atlas_bigmap_needed(species, if (isTRUE(set$totals)) NULL else set$genera)
  }
  missing <- c(setdiff(set$genera, species$genus),
               if (length(set[["species"]])) sprintf("SPCD %d", setdiff(set[["species"]], species$spcd)))
  if (!nrow(species) || length(missing)) {
    stop("BIGMAP no longer offers every host ", if (length(set[["species"]])) "species" else "genus",
         "; missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  species_dir <- file.path(dir, set$species_dir)
  if (!quiet) message("  ", set$id, ": reading ", length(needed), " BIGMAP layers at ",
                      ATLAS_BIGMAP_SAMPLE_M, " m (", length(atlas_bigmap_tiles(window)),
                      " tiles each)")
  bytes <- 0
  for (i in seq_along(needed)) {
    if (!quiet) message("  [", i, "/", length(needed), "] ", needed[[i]])
    got <- atlas_bigmap_fetch_species(needed[[i]], window, species_dir, http = http, quiet = quiet)
    bytes <- bytes + got$bytes
  }
  if (!quiet) message("  ", set$id, ": BIGMAP read, ", round(bytes / 1e9, 2), " GB this run")
  layers <- lapply(needed, function(fn) terra::rast(file.path(species_dir, paste0(fn, ".tif"))))
  names(layers) <- needed
  groups <- atlas_bigmap_groups(species, set$genera, totals = set$totals, spcd = set[["species"]])
  sums <- terra::rast(atlas_group_sums(layers, groups))
  names(sums) <- names(groups)
  atlas_write_raster_whole(sums, out)
  if (!isTRUE(keep_species) && !isTRUE(set$keep_species)) unlink(species_dir, recursive = TRUE)
  terra::rast(out)
}

# ---- NFI -----------------------------------------------------------------

#' What each NFI file holds.
#'
#' Species files are named NFI_MODIS250m_2011_kNN_Species_<Genu>_<Spe>_v1.tif.
#' A "_Spp" file is the trees of that genus not identified to species — part
#' of the genus, NOT a genus total — so a genus is the sum of its species
#' files and its _Spp file. Betu_All is Betula alleghaniensis (yellow birch),
#' not all birches: it is smaller than paper birch in 94% of the pixels where
#' paper birch passes 5%. The needleleaf and broadleaf group files give the
#' total identified trees, and the conifer share.
atlas_nfi_catalog <- function(files, codes = ATLAS_NFI_GENERA, species_codes = NULL) {
  files <- basename(as.character(files))
  species <- "^NFI_MODIS250m_2011_kNN_Species_([A-Za-z]{4})_([A-Za-z]{3})_v1[.]tif$"
  group <- "^NFI_MODIS250m_2011_kNN_SpeciesGroups_(Needleleaf|Broadleaf)_Spp_v1[.]tif$"
  is_species <- grepl(species, files)
  is_group <- grepl(group, files)
  files <- files[is_species | is_group]
  is_species <- grepl(species, files)
  code <- ifelse(is_species, sub(species, "\\1", files), NA_character_)
  genus <- unname(codes[code])
  epithet <- ifelse(is_species, sub(species, "\\2", files), NA_character_)
  # The FIA species a file maps, for a set built by species (ATLAS_NFI_SPECIES).
  spcd <- if (length(species_codes)) unname(species_codes[paste(code, epithet, sep = "_")]) else NA_integer_
  data.frame(
    file = files,
    code = code,
    species = epithet,
    genus = ifelse(is_species, genus, NA_character_),
    spcd = as.integer(spcd),
    group = ifelse(is_species, NA_character_, tolower(sub(group, "\\1", files))),
    stringsAsFactors = FALSE
  )
}

#' The NFI files a host layer needs: the host genera's species and, for the
#' set that carries the totals, the two groups.
atlas_nfi_needed <- function(catalog, groups = TRUE) {
  keep <- !is.na(catalog$genus) | !is.na(catalog$spcd %||% NA) |
    (isTRUE(groups) & !is.na(catalog$group))
  catalog[keep, , drop = FALSE]
}

#' Which NFI files go into each band of the sums.
atlas_nfi_groups <- function(catalog, genera = ATLAS_HOST_GENERA, totals = TRUE, spcd = NULL) {
  groups <- list()
  if (isTRUE(totals)) {
    groups <- list(
      needleleaf = catalog$file[catalog$group %in% "needleleaf"],
      broadleaf = catalog$file[catalog$group %in% "broadleaf"]
    )
    if (length(groups$needleleaf) != 1L || length(groups$broadleaf) != 1L) {
      stop("the NFI listing is missing its needleleaf or broadleaf group", call. = FALSE)
    }
  }
  for (genus in genera) {
    groups[[tolower(genus)]] <- catalog$file[catalog$genus %in% genus]
  }
  if (length(spcd)) {
    parts <- sub("^host_", "", atlas_host_species_bands(spcd))
    for (i in seq_along(spcd)) {
      groups[[parts[[i]]]] <- catalog$file[catalog$spcd %in% spcd[[i]]]
    }
  }
  groups
}

#' The files NFI's 2011 directory lists.
atlas_nfi_list <- function(http = atlas_host_http, base = ATLAS_NFI_URL) {
  dest <- tempfile(fileext = ".html")
  on.exit(unlink(dest), add = TRUE)
  atlas_fetch_file(paste0(base, "/"), dest, http = http)
  html <- paste(readLines(dest, warn = FALSE), collapse = "\n")
  links <- regmatches(html, gregexpr("href=\"NFI_[^\"]+[.]tif\"", html))[[1]]
  unique(sub("^href=\"", "", sub("\"$", "", links)))
}

#' One NFI band averaged from its own 250 m cells onto the grid's 1 km cells,
#' written to `filename`. Each band is a file, not memory: the species layer
#' has 316, about 200 MB each in memory, and holding them all ran out of it.
#' A band already written is read back, so an interrupted build resumes.
atlas_nfi_project <- function(x, target, filename) {
  if (file.exists(filename)) {
    return(terra::rast(filename))
  }
  part <- paste0(filename, ".part.tif")
  unlink(part)
  terra::project(x, target, method = "average", filename = part, overwrite = TRUE,
                 gdal = c("COMPRESS=DEFLATE"))
  if (!file.rename(part, filename)) {
    stop("could not move ", basename(part), " into place", call. = FALSE)
  }
  terra::rast(filename)
}

#' NFI summed into bands on 1 km cells: identified trees (needleleaf plus
#' broadleaf), conifer, and each host genus, all as mean percent of a cell.
#'
#' Each genus is summed at NFI's own 250 m first, then averaged onto the grid:
#' one reprojection per band rather than one per file.
atlas_nfi_sums <- function(dir, http = atlas_host_http, quiet = FALSE, files = NULL,
                           set = atlas_host_set("hosts")) {
  out <- file.path(dir, set$nfi)
  if (file.exists(out)) {
    return(terra::rast(out))
  }
  nfi_dir <- file.path(dir, set$nfi_dir)
  dir.create(nfi_dir, recursive = TRUE, showWarnings = FALSE)
  # The bands on 1 km cells, one file each until they are summed into `out`.
  band_dir <- paste0(nfi_dir, "-bands")
  dir.create(band_dir, recursive = TRUE, showWarnings = FALSE)
  catalog <- atlas_nfi_needed(atlas_nfi_catalog(files %||% atlas_nfi_list(http), set$nfi_codes,
                                                species_codes = set$nfi_species),
                              groups = set$totals)
  for (file in catalog$file) {
    dest <- file.path(nfi_dir, file)
    if (file.exists(dest)) next
    if (!quiet) message("  ", set$id, ": downloading ", file)
    atlas_fetch_file(paste0(ATLAS_NFI_URL, "/", file), dest, http = http, check = atlas_is_tiff)
  }

  first <- terra::rast(file.path(nfi_dir, catalog$file[[1]]))
  target <- atlas_window_template(atlas_extent_in_grid(first), ATLAS_HOST_BASE_M)
  groups <- atlas_nfi_groups(catalog, set$genera, totals = set$totals, spcd = set[["species"]])
  # A genus or species NFI does not map is none of Canada's identified trees:
  # the same 0 band for every one of them, so it is projected once. Most of
  # the species layer's 316 bands are such, and projecting each took minutes.
  absent <- NULL
  bands <- lapply(names(groups), function(band) {
    members <- groups[[band]]
    if (!quiet) message("  ", set$id, ": NFI ", band, " (", length(members), " file(s))")
    if (!length(members)) {
      if (is.null(absent)) {
        absent <<- atlas_nfi_project(terra::ifel(is.na(first), NA, 0), target,
                                     file.path(band_dir, "_absent.tif"))
      }
      return(absent)
    }
    native <- terra::rast(file.path(nfi_dir, members))
    summed <- if (length(members) == 1L) native else terra::app(native, sum)
    atlas_nfi_project(summed, target, file.path(band_dir, paste0(band, ".tif")))
  })
  names(bands) <- names(groups)
  parts <- atlas_host_set_parts(set)
  sums <- if (isTRUE(set$totals)) {
    terra::rast(c(
      list(total = bands$needleleaf + bands$broadleaf, conifer = bands$needleleaf),
      bands[parts]
    ))
  } else {
    terra::rast(bands[parts])
  }
  names(sums) <- c(if (isTRUE(set$totals)) c("total", "conifer"), parts)
  atlas_write_raster_whole(sums, out)
  unlink(band_dir, recursive = TRUE)
  terra::rast(out)
}

# ---- boundaries, windows, masks -------------------------------------------

#' The lower 48 and DC, from the Census cartographic boundaries.
atlas_conus_states <- function(dir, http = atlas_host_http) {
  zip <- file.path(dir, basename(ATLAS_CONUS_URL))
  if (!file.exists(zip)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    atlas_fetch_file(ATLAS_CONUS_URL, zip, http = http, check = atlas_is_zip)
  }
  layer <- sub("[.]zip$", ".shp", basename(zip))
  states <- terra::vect(paste0("/vsizip/", normalizePath(zip, winslash = "/"), "/", layer))
  states <- states[!states$STUSPS %in% ATLAS_NOT_CONUS, ]
  terra::project(states, ATLAS_CRS)
}

#' The grid-aligned window around a raster or vector, in grid coordinates.
atlas_extent_in_grid <- function(x) {
  box <- terra::ext(x)
  if (!terra::same.crs(terra::crs(x), ATLAS_CRS)) {
    # The edges of a box bend in another projection, so they are sampled all
    # along, not only at the corners.
    edge <- as.matrix(expand.grid(
      x = seq(box$xmin, box$xmax, length.out = 60),
      y = seq(box$ymin, box$ymax, length.out = 60)
    ))
    box <- terra::ext(terra::project(terra::vect(edge, crs = terra::crs(x)), ATLAS_CRS))
  }
  atlas_snap_window(box$xmin, box$xmax, box$ymin, box$ymax)
}

#' An empty raster over a window, on the grid's origin.
atlas_window_template <- function(window, res) {
  terra::rast(
    xmin = window[["xmin"]], xmax = window[["xmax"]],
    ymin = window[["ymin"]], ymax = window[["ymax"]],
    resolution = res, crs = ATLAS_CRS
  )
}

#' Where BIGMAP speaks for a cell: every cell the lower 48 touches (`inside`),
#' and the cells whose centre is in them (`first`, for the border).
atlas_host_masks <- function(states, template) {
  touched <- terra::rasterize(states, template, touches = TRUE)
  centred <- terra::rasterize(states, template)
  list(inside = !is.na(touched), first = !is.na(centred))
}

# ---- building the layer ---------------------------------------------------

#' Build the host layer on a grid.
#'
#' Both inventories are summed onto 1 km cells once, under raw_dir/hosts, and
#' each grid is made from those sums: averaged up for a coarser grid, and only
#' then turned into shares, so a 5 km share is biomass-weighted across the
#' whole cell rather than an average of 1 km shares.
atlas_build_hosts <- function(raw_dir, grid = "draft", http = atlas_host_http, quiet = FALSE,
                              set = atlas_host_set("hosts")) {
  res <- atlas_resolution(grid)
  if (res %% ATLAS_HOST_BASE_M) {
    stop("the host layer is built from 1 km sums; ", grid, " is not a multiple", call. = FALSE)
  }
  dir <- file.path(raw_dir, "hosts")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  production <- atlas_host_set("hosts")
  if (!isTRUE(set$totals)) {
    # Checked before anything is read: without them the set's genera
    # would be shares of nothing.
    cached <- file.path(dir, c(production$bigmap, production$nfi))
    if (!all(file.exists(cached))) {
      stop(set$id, " takes its tree totals from the host layer's sums (",
           paste(basename(cached), collapse = ", "), " under ", dir,
           "): build hosts first", call. = FALSE)
    }
  }

  states <- atlas_conus_states(dir, http)
  us_window <- atlas_extent_in_grid(states)
  us_sums <- atlas_bigmap_sums(dir, us_window, http = http, quiet = quiet, set = set)
  ca_sums <- atlas_nfi_sums(dir, http = http, quiet = quiet, set = set)
  if (!isTRUE(set$totals)) {
    us_sums <- atlas_with_host_total(us_sums, file.path(dir, production$bigmap))
    ca_sums <- atlas_with_host_total(ca_sums, file.path(dir, production$nfi))
  }

  if (!quiet) message("  ", set$id, ": shares on the ", grid, " grid")
  built <- atlas_combine_hosts(us_sums, ca_sums, states, res, bands = atlas_host_set_bands(set))
  terra::extend(built, atlas_grid_template(grid))
}

#' Build the decay-host layer on a grid (R/layers.R, hostsdecay).
atlas_build_decay_hosts <- function(raw_dir, grid = "draft") {
  atlas_build_hosts(raw_dir, grid, set = atlas_host_set("hostsdecay"))
}

#' Build the tree-species layer on a grid (R/layers.R, hostspecies).
atlas_build_species_hosts <- function(raw_dir, grid = "draft") {
  atlas_build_hosts(raw_dir, grid, set = atlas_host_set("hostspecies"))
}

#' Put production's tree total in front of a second set's genus sums, so
#' each genus becomes a share of the same whole the production genera are.
#' Read, never written: the production cache is only opened.
atlas_with_host_total <- function(sums, total_path) {
  total <- terra::rast(total_path)[["total"]]
  if (!terra::compareGeom(total, sums, stopOnError = FALSE)) {
    stop("the host total in ", basename(total_path), " is not on the same 1 km cells as ",
         "the set's genus sums", call. = FALSE)
  }
  out <- c(total, sums)
  names(out) <- c("total", names(sums))
  out
}

#' Turn the two inventories' 1 km sums into host shares at a cell size:
#' average the sums up to it, divide, keep BIGMAP to the lower 48 (touching
#' cells, with 0 where it found no trees), and mosaic with Canada. Returns the
#' window the two cover, on the grid's origin.
atlas_combine_hosts <- function(us_sums, ca_sums, states, res, bands = ATLAS_HOST_BANDS) {
  fact <- res / ATLAS_HOST_BASE_M
  if (fact > 1) {
    us_sums <- terra::aggregate(us_sums, fact, fun = "mean", na.rm = TRUE)
    ca_sums <- terra::aggregate(ca_sums, fact, fun = "mean", na.rm = TRUE)
  }
  both <- terra::union(terra::ext(us_sums), terra::ext(ca_sums))
  window <- atlas_snap_window(both$xmin, both$xmax, both$ymin, both$ymax, step = res)
  template <- atlas_window_template(window, res)
  us_sums <- terra::extend(us_sums, template)
  ca_sums <- terra::extend(ca_sums, template)

  masks <- atlas_host_masks(states, template)
  us <- atlas_inventory_fill(atlas_host_shares(us_sums), masks$inside)
  canada <- atlas_host_shares(ca_sums)
  built <- atlas_mosaic_hosts(us, canada, masks$first)
  if (!identical(names(built), bands)) {
    stop("host shares came out as ", paste(names(built), collapse = ", "),
         ", not ", paste(bands, collapse = ", "), call. = FALSE)
  }
  built
}

# ---- HTTP ----------------------------------------------------------------

#' Fetch one URL to a file; returns the HTTP status. Replaced in tests, which
#' never reach the network.
atlas_host_http <- function(url, dest) {
  handle <- curl::new_handle()
  curl::handle_setopt(handle, connecttimeout = 60, timeout = 1800, followlocation = TRUE)
  curl::handle_setheaders(handle, "User-Agent" = "MycoMap Atlas layer build (mycomap.org)")
  curl::curl_fetch_disk(url, dest, handle = handle)$status_code
}

#' Fetch a file, politely: one request at a time, retried with a growing wait
#' when the server is busy or failing (429, 5xx, or a dropped connection),
#' refused at once on any other error. `check` rejects a body that came back
#' 200 but is not the file: ArcGIS reports its errors as JSON with status 200,
#' and those are retried too. The file appears only when complete.
atlas_fetch_file <- function(url, dest, http = atlas_host_http, check = NULL,
                             tries = 5L, wait = 15) {
  part <- paste0(dest, ".part")
  on.exit(unlink(part), add = TRUE)
  for (attempt in seq_len(tries)) {
    status <- tryCatch(as.integer(http(url, part)), error = function(e) NA_integer_)
    if (identical(status, 200L) && file.exists(part) && (is.null(check) || isTRUE(check(part)))) {
      file.rename(part, dest)
      return(invisible(dest))
    }
    retry <- is.na(status) || status == 200L || status == 429L || status >= 500L
    if (!retry) {
      stop("HTTP ", status, " for ", url, call. = FALSE)
    }
    if (attempt < tries) Sys.sleep(wait * 2^(attempt - 1L))
  }
  stop("gave up after ", tries, " tries (last: ",
       if (is.na(status)) "no response" else paste("HTTP", status), ") for ", url, call. = FALSE)
}

#' Whether a file starts like a TIFF (classic or BigTIFF, either byte order).
atlas_is_tiff <- function(path) {
  head <- readBin(path, "raw", n = 4L)
  length(head) == 4L && (
    identical(head, as.raw(c(0x49, 0x49, 0x2a, 0x00))) ||
      identical(head, as.raw(c(0x4d, 0x4d, 0x00, 0x2a))) ||
      identical(head, as.raw(c(0x49, 0x49, 0x2b, 0x00))) ||
      identical(head, as.raw(c(0x4d, 0x4d, 0x00, 0x2b)))
  )
}

#' Whether a file starts like a zip archive.
atlas_is_zip <- function(path) {
  identical(readBin(path, "raw", n = 4L), as.raw(c(0x50, 0x4b, 0x03, 0x04)))
}
