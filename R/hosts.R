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
atlas_bigmap_species <- function(functions) {
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
    host = genus %in% ATLAS_HOST_GENERA,
    conifer = spcd >= 1L & spcd < 300L,
    stringsAsFactors = FALSE
  )
}

#' The raster functions to read: every species, because every species is part
#' of the total a share is taken over.
atlas_bigmap_needed <- function(species) {
  species$fn
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
atlas_bigmap_groups <- function(species) {
  groups <- list(
    total = species$fn,
    conifer = species$fn[species$conifer]
  )
  for (genus in ATLAS_HOST_GENERA) {
    groups[[tolower(genus)]] <- species$fn[species$genus == genus]
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
  terra::writeRaster(merged, out, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
  if (!quiet) message("    ", fn, ": ", round(bytes / 1e6, 1), " MB")
  invisible(list(path = out, bytes = bytes))
}

#' BIGMAP summed into bands on 1 km cells: the biomass of every species,
#' of the conifers, and of each host genus. The species files are removed once
#' summed.
atlas_bigmap_sums <- function(dir, window, http = atlas_host_http, quiet = FALSE,
                              functions = NULL, keep_species = FALSE) {
  out <- file.path(dir, "bigmap-1km.tif")
  if (file.exists(out)) {
    return(terra::rast(out))
  }
  functions <- functions %||% atlas_bigmap_functions(http)
  species <- atlas_bigmap_species(functions)
  needed <- atlas_bigmap_needed(species)
  missing <- setdiff(ATLAS_HOST_GENERA, species$genus)
  if (!nrow(species) || length(missing)) {
    stop("BIGMAP no longer offers every host genus; missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  species_dir <- file.path(dir, "bigmap-species")
  if (!quiet) message("  hosts: reading ", length(needed), " BIGMAP layers at ",
                      ATLAS_BIGMAP_SAMPLE_M, " m (", length(atlas_bigmap_tiles(window)),
                      " tiles each)")
  bytes <- 0
  for (i in seq_along(needed)) {
    if (!quiet) message("  [", i, "/", length(needed), "] ", needed[[i]])
    got <- atlas_bigmap_fetch_species(needed[[i]], window, species_dir, http = http, quiet = quiet)
    bytes <- bytes + got$bytes
  }
  if (!quiet) message("  hosts: BIGMAP read, ", round(bytes / 1e9, 2), " GB this run")
  layers <- lapply(needed, function(fn) terra::rast(file.path(species_dir, paste0(fn, ".tif"))))
  names(layers) <- needed
  sums <- terra::rast(atlas_group_sums(layers, atlas_bigmap_groups(species)))
  names(sums) <- c("total", "conifer", tolower(ATLAS_HOST_GENERA))
  terra::writeRaster(sums, out, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
  if (!isTRUE(keep_species)) unlink(species_dir, recursive = TRUE)
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
atlas_nfi_catalog <- function(files) {
  files <- basename(as.character(files))
  species <- "^NFI_MODIS250m_2011_kNN_Species_([A-Za-z]{4})_([A-Za-z]{3})_v1[.]tif$"
  group <- "^NFI_MODIS250m_2011_kNN_SpeciesGroups_(Needleleaf|Broadleaf)_Spp_v1[.]tif$"
  is_species <- grepl(species, files)
  is_group <- grepl(group, files)
  files <- files[is_species | is_group]
  is_species <- grepl(species, files)
  code <- ifelse(is_species, sub(species, "\\1", files), NA_character_)
  genus <- unname(ATLAS_NFI_GENERA[code])
  data.frame(
    file = files,
    code = code,
    species = ifelse(is_species, sub(species, "\\2", files), NA_character_),
    genus = ifelse(is_species, genus, NA_character_),
    group = ifelse(is_species, NA_character_, tolower(sub(group, "\\1", files))),
    stringsAsFactors = FALSE
  )
}

#' The NFI files a host layer needs: the host genera's species and the two
#' groups.
atlas_nfi_needed <- function(catalog) {
  catalog[!is.na(catalog$genus) | !is.na(catalog$group), , drop = FALSE]
}

#' Which NFI files go into each band of the sums.
atlas_nfi_groups <- function(catalog) {
  groups <- list(
    needleleaf = catalog$file[catalog$group %in% "needleleaf"],
    broadleaf = catalog$file[catalog$group %in% "broadleaf"]
  )
  if (length(groups$needleleaf) != 1L || length(groups$broadleaf) != 1L) {
    stop("the NFI listing is missing its needleleaf or broadleaf group", call. = FALSE)
  }
  for (genus in ATLAS_HOST_GENERA) {
    groups[[tolower(genus)]] <- catalog$file[catalog$genus %in% genus]
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

#' NFI summed into bands on 1 km cells: identified trees (needleleaf plus
#' broadleaf), conifer, and each host genus, all as mean percent of a cell.
#'
#' Each genus is summed at NFI's own 250 m first, then averaged onto the grid:
#' one reprojection per band rather than one per file.
atlas_nfi_sums <- function(dir, http = atlas_host_http, quiet = FALSE, files = NULL) {
  out <- file.path(dir, "nfi-1km.tif")
  if (file.exists(out)) {
    return(terra::rast(out))
  }
  nfi_dir <- file.path(dir, "nfi")
  dir.create(nfi_dir, recursive = TRUE, showWarnings = FALSE)
  catalog <- atlas_nfi_needed(atlas_nfi_catalog(files %||% atlas_nfi_list(http)))
  for (file in catalog$file) {
    dest <- file.path(nfi_dir, file)
    if (file.exists(dest)) next
    if (!quiet) message("  hosts: downloading ", file)
    atlas_fetch_file(paste0(ATLAS_NFI_URL, "/", file), dest, http = http, check = atlas_is_tiff)
  }

  first <- terra::rast(file.path(nfi_dir, catalog$file[[1]]))
  target <- atlas_window_template(atlas_extent_in_grid(first), ATLAS_HOST_BASE_M)
  groups <- atlas_nfi_groups(catalog)
  bands <- lapply(names(groups), function(band) {
    members <- groups[[band]]
    if (!quiet) message("  hosts: NFI ", band, " (", length(members), " file(s))")
    if (!length(members)) {
      # A genus NFI does not map: none of Canada's identified trees.
      return(terra::project(terra::ifel(is.na(first), NA, 0), target, method = "average"))
    }
    native <- terra::rast(file.path(nfi_dir, members))
    summed <- if (length(members) == 1L) native else terra::app(native, sum)
    terra::project(summed, target, method = "average")
  })
  names(bands) <- names(groups)
  sums <- terra::rast(c(
    list(total = bands$needleleaf + bands$broadleaf, conifer = bands$needleleaf),
    bands[tolower(ATLAS_HOST_GENERA)]
  ))
  names(sums) <- c("total", "conifer", tolower(ATLAS_HOST_GENERA))
  terra::writeRaster(sums, out, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
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
atlas_build_hosts <- function(raw_dir, grid = "draft", http = atlas_host_http, quiet = FALSE) {
  res <- atlas_resolution(grid)
  if (res %% ATLAS_HOST_BASE_M) {
    stop("the host layer is built from 1 km sums; ", grid, " is not a multiple", call. = FALSE)
  }
  dir <- file.path(raw_dir, "hosts")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  states <- atlas_conus_states(dir, http)
  us_window <- atlas_extent_in_grid(states)
  us_sums <- atlas_bigmap_sums(dir, us_window, http = http, quiet = quiet)
  ca_sums <- atlas_nfi_sums(dir, http = http, quiet = quiet)

  if (!quiet) message("  hosts: shares on the ", grid, " grid")
  built <- atlas_combine_hosts(us_sums, ca_sums, states, res)
  terra::extend(built, atlas_grid_template(grid))
}

#' Turn the two inventories' 1 km sums into host shares at a cell size:
#' average the sums up to it, divide, keep BIGMAP to the lower 48 (touching
#' cells, with 0 where it found no trees), and mosaic with Canada. Returns the
#' window the two cover, on the grid's origin.
atlas_combine_hosts <- function(us_sums, ca_sums, states, res) {
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
  names(built) <- ATLAS_HOST_BANDS
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
