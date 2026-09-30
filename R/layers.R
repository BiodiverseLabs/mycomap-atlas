# Environmental layers.
#
# Every layer must cover all of North America, because the grid does. That
# rules out the obvious United States products — TreeMap, NLCD, PAD-US stop at
# the lower 48, and British Columbia alone holds 8% of the records — so the
# registry uses global sources and accepts their coarser detail.
#
# The exception is the host-tree layer (R/hosts.R). No continental map of
# tree species exists, so it joins the United States inventory to Canada's,
# and neither speaks for Alaska, Hawaii, Puerto Rico or Mexico. A layer's gap
# must not take ground away from every model, so there the shares are filled
# with 0 and a band beside them (host_known) says the inventories were silent:
# the ground stays in every fit and on every map, and a model can tell "no
# such trees" from "nobody mapped the trees" (atlas_fill_outside).
#
# Sources are brought onto the grid by averaging the source cells each grid
# cell covers, never by interpolation. Interpolating a 1 km source onto a 5 km
# cell reads only the four source cells nearest its centre, so the cell is a
# sample rather than a description, and it comes out empty if any of the four
# is empty: measured at the records, that cost soil 10,321 records against
# 117. Averaging keeps every cell that holds any data. What is still empty
# on land afterwards, coastal cells mostly, is filled from the cells around it
# up to ATLAS_FILL_NEAR_KM away (atlas_fill_near), where land is wherever the
# land-cover layer has data, the finest coastline among the sources; land
# cover is therefore built first.
#
# Production fits on ATLAS_PRODUCTION_LAYERS (R/layersweep.R). The rest are
# candidates, measured by atlas sweep-layers before any is fitted on in
# production. Building a layer is what puts it into every fit on that grid,
# so a candidate is built only into a separate data directory until it is
# chosen. Measured on 152 taxa (2026-09-30): host trees earned their place
# (+0.008 +/- 0.004 AUC, the second most important layer after climate);
# forest type was kept; water balance is held; carbonate bedrock, landform
# (wetness, northness, heat load) and a second host layer from USFS basal
# area added nothing and were dropped. More of SoilGrids, measured on 158
# taxa (2026-09-30): pH at 15-30 cm is a copy of surface pH (Maxent never
# kept it; the forest valued it exactly as surface pH), and bulk density with
# coarse fragments made Maxent slightly worse (-0.0008 +/- 0.0004 AUC), so
# both were dropped. Total nitrogen was neutral (+0.0001 +/- 0.0003 AUC) and
# joined the soil layer on ecological grounds (Steve): fungal communities,
# ectomycorrhizal ones above all, are known to follow soil nitrogen. Round 2,
# on the same 158 taxa (2026-09-30): the host trees of wood-decay and
# parasitic fungi (maple, ash, elm, juniper, cedar, tulip tree, cherry,
# sweetgum, sycamore, black locust) came out +0.0018 +/- 0.0013 AUC overall
# and +0.004 for taxa with 30-49 sites, maple doing most of the work, and
# were added as the decay-host layer on that and on ecology; cropland, bare
# ground and moss/lichen from WorldCover made Maxent slightly worse
# (-0.0019 +/- 0.0009 AUC) and were dropped.

#' Rename WorldClim's bioclim bands to bio1..bio19, in numeric order.
#'
#' The band number is read from each name rather than assumed from position: a
#' silently mislabelled bio variable would be a wrong model that still looks
#' right.
atlas_rename_bioclim <- function(x) {
  names_in <- names(x)
  number <- suppressWarnings(as.integer(sub("^.*bio_?", "", names_in)))
  if (anyNA(number) || anyDuplicated(number)) {
    stop("cannot read bioclim band numbers from: ",
         paste(names_in, collapse = ", "), call. = FALSE)
  }
  x <- x[[order(number)]]
  names(x) <- paste0("bio", sort(number))
  x
}

#' Source resolution, in arc-minutes, for a named grid.
atlas_source_resolution <- function(grid = "draft") {
  sources <- c(draft = 2.5, production = 0.5)
  if (!is.character(grid) || length(grid) != 1 || !grid %in% names(sources)) {
    stop("grid must be one of: ", paste(names(sources), collapse = ", "), call. = FALSE)
  }
  unname(sources[[grid]])
}

#' Every layer Atlas knows how to build.
atlas_layer_registry <- function() {
  list(
    elevation = list(
      id = "elevation",
      title = "Elevation",
      source = "WorldClim 2.1 (SRTM)",
      url = "https://worldclim.org/data/worldclim21.html",
      license = "CC BY-SA 4.0",
      citation = "Fick SE, Hijmans RJ (2017) WorldClim 2. Int J Climatol 37:4302-4315",
      method = "average",
      fill_near = TRUE,
      fetch = function(path, res) geodata::elevation_global(res = res, path = path),
      rename = function(x) {
        names(x) <- "elevation"
        x
      }
    ),
    bioclim = list(
      id = "bioclim",
      title = "Bioclimatic variables (bio1-bio19)",
      source = "WorldClim 2.1, 1970-2000",
      url = "https://worldclim.org/data/worldclim21.html",
      license = "CC BY-SA 4.0",
      citation = "Fick SE, Hijmans RJ (2017) WorldClim 2. Int J Climatol 37:4302-4315",
      method = "average",
      fill_near = TRUE,
      fetch = function(path, res) geodata::worldclim_global(var = "bio", res = res, path = path),
      rename = atlas_rename_bioclim
    ),
    terrain = list(
      id = "terrain",
      title = "Slope and terrain roughness",
      source = "Derived from the elevation layer on this grid",
      url = NA_character_,
      license = "Follows the elevation layer",
      citation = "Derived with terra::terrain()",
      method = "average",
      depends = "elevation",
      # Slope needs a cell's neighbours, so computed naively every coastal cell
      # comes back empty — which cost 10.7% of the records, most of them on the
      # British Columbia and Pacific coasts where the collecting is. Sea level
      # is filled in as 0 first, so a shoreline has the slope it really has,
      # and the land mask is restored afterwards.
      derive = function(elevation) {
        at_sea_level <- terra::ifel(is.na(elevation), 0, elevation)
        out <- terra::terrain(at_sea_level, v = c("slope", "TRI"), unit = "degrees")
        names(out) <- c("slope", "roughness")
        terra::mask(out, elevation)
      }
    ),
    soil = list(
      id = "soil",
      title = "Soil pH, carbon, nitrogen, texture and exchange capacity (0-5 cm)",
      source = "SoilGrids 2.0",
      url = "https://soilgrids.org",
      license = "CC BY 4.0",
      citation = "Poggio L et al. (2021) SoilGrids 2.0. SOIL 7:217-240",
      method = "average",
      fill_near = TRUE,
      # Downloaded rather than read remotely. SoilGrids' own service serves the
      # native 250 m grid — 58,034 x 159,246 cells in Interrupted Goode
      # Homolosine — and a continental window of that is a billion pixels to
      # pull over HTTP for a 5 km layer. geodata's pre-aggregated copy is the
      # right source for a grid this size.
      fetch = function(path, res) {
        vars <- c("phh2o", "soc", "nitrogen", "clay", "sand", "cec")
        parts <- lapply(vars, function(v) {
          geodata::soil_world(var = v, depth = 5, stat = "mean", path = path)
        })
        out <- terra::rast(parts)
        names(out) <- paste0("soil_", vars)
        out
      }
    ),
    landcover = list(
      id = "landcover",
      title = "Fractional land cover",
      # geodata serves ESA WorldCover aggregated to 30 arc-seconds, not
      # Copernicus Global Land Cover. Checked against the files it downloads.
      source = "ESA WorldCover 2021 v200, aggregated to 30 arc-seconds by geodata",
      url = "https://esa-worldcover.org",
      license = "CC BY 4.0",
      citation = "Zanaga D et al. (2022) ESA WorldCover 10 m 2021 v200",
      method = "average",
      note = "Tree cover is a fraction, not host identity.",
      fetch = function(path, res) {
        vars <- c("trees", "shrubs", "grassland", "wetland", "water", "built")
        parts <- lapply(vars, function(v) geodata::landcover(var = v, path = path))
        out <- terra::rast(parts)
        names(out) <- paste0("cover_", vars)
        out
      }
    ),
    hosts = list(
      id = "hosts",
      title = "Host trees: share of trees by genus, and conifer share",
      source = "USFS FIA BIGMAP 2018 (lower 48) and Canada NFI kNN 2011",
      url = ATLAS_BIGMAP_URL,
      urls = c(ATLAS_BIGMAP_URL, ATLAS_NFI_URL, ATLAS_CONUS_URL),
      license = "BIGMAP: US public domain; NFI: Open Government Licence - Canada",
      citation = paste(
        "Wilson BT, Knight JF, McRoberts RE (2018) Harmonic regression of Landsat time series",
        "for modeling attributes from national forest inventory data. ISPRS J Photogramm",
        "Remote Sens 137:29-46; Beaudoin A et al. (2014) Mapping attributes of Canada's",
        "forests at moderate resolution through kNN and MODIS imagery. Can J For Res",
        "44:521-532, doi:10.1139/cjfr-2013-0401"
      ),
      method = "share of genus in total trees; BIGMAP sampled at 250 m and block-averaged, NFI area-averaged",
      note = paste(
        "Lower 48 and Canada only. Alaska, Hawaii, Puerto Rico and Mexico have no tree",
        "inventory here: their shares are 0 and host_known is 0."
      ),
      fill_outside = "host_known",
      # Built on the grid directly, not fetched and reprojected: BIGMAP is read
      # in the grid's own projection, and both inventories need summing by
      # genus before anything is averaged.
      build = function(raw_dir, grid) atlas_build_hosts(raw_dir, grid)
    ),
    # The trees wood-decay and parasitic fungi live on, beside the host layer's
    # mostly mycorrhizal partners (R/hosts.R, ATLAS_DECAY_HOST_GENERA): shares
    # of the same tree totals, from the same inventories.
    hostsdecay = list(
      id = "hostsdecay",
      title = "Decay and parasite hosts: share of trees by genus",
      source = "USFS FIA BIGMAP 2018 (lower 48) and Canada NFI kNN 2011",
      url = ATLAS_BIGMAP_URL,
      urls = c(ATLAS_BIGMAP_URL, ATLAS_NFI_URL, ATLAS_CONUS_URL),
      license = "BIGMAP: US public domain; NFI: Open Government Licence - Canada",
      citation = paste(
        "Wilson BT, Knight JF, McRoberts RE (2018) Harmonic regression of Landsat time series",
        "for modeling attributes from national forest inventory data. ISPRS J Photogramm",
        "Remote Sens 137:29-46; Beaudoin A et al. (2014) Mapping attributes of Canada's",
        "forests at moderate resolution through kNN and MODIS imagery. Can J For Res",
        "44:521-532, doi:10.1139/cjfr-2013-0401"
      ),
      method = "share of genus in the host layer's total trees; BIGMAP sampled at 250 m and block-averaged, NFI area-averaged",
      note = paste(
        "Lower 48 and Canada only. Alaska, Hawaii, Puerto Rico and Mexico have no tree",
        "inventory here: their shares are 0, and the host layer's host_known is 0 there.",
        "NFI does not map tulip tree, sweetgum, sycamore or black locust: 0 in Canada."
      ),
      bands = ATLAS_HOST_DECAY_BANDS,
      # Filled as the host layer is, without a flag of its own. The two layers
      # are read from the same two inventories inside the same lower-48
      # boundary, so the inventories are silent on exactly the ground where
      # the host layer's host_known is 0; a second flag would be a copy of it
      # under another name, and the host layer is always fitted beside this
      # one. Without the fill, the ground no inventory covers would drop out
      # of every fit on the grid.
      fill_outside = "host_known",
      fill_flag = FALSE,
      build = function(raw_dir, grid) atlas_build_decay_hosts(raw_dir, grid)
    ),
    foresttype = list(
      id = "foresttype",
      title = "Needleleaf, broadleaf and mixed forest",
      source = "NALCMS Land Cover 2020 v2, 30 m (CEC)",
      url = "https://www.cec.org/north-american-environmental-atlas/land-cover-30m-2020/",
      license = "CC BY 4.0",
      citation = paste(
        "Commission for Environmental Cooperation (2024) North American Environmental",
        "Atlas - Land Cover 2020 30m. NALCMS; CCRS, USGS, CONABIO, CONAFOR, INEGI. Ed. 2.0"
      ),
      note = paste(
        "Share of each cell under each forest type, counted from 30 m pixels. Hawaii and",
        "the Caribbean islands, which NALCMS does not map, are filled from Copernicus",
        "Global Land Cover 2019 (100 m, CC BY 4.0), and forest_known is 0 there."
      ),
      method = "average",
      fetch = function(path, res) atlas_nalcms_source(path),
      # Wherever the main source is empty and the supplement is not.
      supplement = function(path, res) atlas_copernicus_source(path),
      supplement_known = "forest_known"
    ),
    waterbalance = list(
      id = "waterbalance",
      title = "Moisture deficit, autumn climate, snow, humidity, AET and VPD",
      source = "AdaptWest ClimateNA v7.3 normals 1991-2020, 1 km; TerraClimate 1991-2020",
      url = "https://adaptwest.databasin.org/pages/adaptwest-climatena/",
      license = "CC BY 4.0 (AdaptWest); CC0 (TerraClimate)",
      citation = paste(
        "AdaptWest Project (2022) Gridded current and projected climate data for North",
        "America at 1km resolution, ClimateNA v7.30; Wang T, Hamann A, Spittlehouse D,",
        "Carroll C (2016) PLoS One 11:e0156720; Abatzoglou JT et al. (2018)",
        "TerraClimate. Scientific Data 5:170191"
      ),
      method = "average",
      fetch = function(path, res) atlas_waterbalance_source(path)
    )
  )
}

atlas_layer_dir <- function(grid = "draft") {
  atlas_path("layers", grid)
}

atlas_layer_path <- function(id, grid = "draft") {
  file.path(atlas_layer_dir(grid), paste0(id, ".tif"))
}

atlas_manifest_path <- function(grid = "draft") {
  file.path(atlas_layer_dir(grid), "manifest.json")
}

#' Everything built on a grid so far.
atlas_layer_manifest <- function(grid = "draft") {
  path <- atlas_manifest_path(grid)
  if (!file.exists(path)) {
    return(list())
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

#' Add or replace one layer's entry, keeping the rest.
atlas_record_layer <- function(entry, grid = "draft") {
  manifest <- atlas_layer_manifest(grid)
  ids <- vapply(manifest, function(x) as.character(x$id), character(1))
  manifest <- manifest[ids != entry$id]
  manifest[[length(manifest) + 1L]] <- entry
  order <- order(vapply(manifest, function(x) as.character(x$id), character(1)))
  manifest <- manifest[order]
  atlas_write_json(manifest, atlas_manifest_path(grid))
  invisible(manifest)
}

# Albers is undefined on the far side of the globe, so a worldwide source has
# to be cut down before it is projected: warping the whole planet into a North
# American cone fails outright. The window is generous — wider than the grid,
# well inside the projection's valid domain — so nothing the grid can show is
# cut away.
ATLAS_SOURCE_WINDOW <- c(xmin = -180, xmax = -40, ymin = 5, ymax = 85)

#' The region window, expressed in a source's own coordinate system.
#'
#' Sources are not all in longitude and latitude: SoilGrids is 58,034 x 159,246
#' cells in Interrupted Goode Homolosine. Projecting the window into the
#' source's own system is what makes a crop possible at all — without it, terra
#' is asked to warp nine billion cells and simply grinds.
atlas_region_window <- function(crs_out) {
  longitudes <- seq(ATLAS_SOURCE_WINDOW[["xmin"]], ATLAS_SOURCE_WINDOW[["xmax"]], by = 2)
  latitudes <- seq(ATLAS_SOURCE_WINDOW[["ymin"]], ATLAS_SOURCE_WINDOW[["ymax"]], by = 2)
  edge <- rbind(
    cbind(longitudes, ATLAS_SOURCE_WINDOW[["ymin"]]),
    cbind(longitudes, ATLAS_SOURCE_WINDOW[["ymax"]]),
    cbind(ATLAS_SOURCE_WINDOW[["xmin"]], latitudes),
    cbind(ATLAS_SOURCE_WINDOW[["xmax"]], latitudes),
    # Interrupted projections bend in the middle, so the interior counts too.
    as.matrix(expand.grid(x = longitudes, y = latitudes))
  )
  colnames(edge) <- c("x", "y")
  points <- terra::vect(edge, crs = "EPSG:4326")
  terra::ext(terra::project(points, crs_out))
}

#' Cut a source down to the region before projecting it onto the grid.
atlas_crop_to_region <- function(x) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed to build layers: install.packages('terra')", call. = FALSE)
  }
  window <- if (terra::is.lonlat(x)) {
    terra::ext(
      ATLAS_SOURCE_WINDOW[["xmin"]], ATLAS_SOURCE_WINDOW[["xmax"]],
      ATLAS_SOURCE_WINDOW[["ymin"]], ATLAS_SOURCE_WINDOW[["ymax"]]
    )
  } else {
    atlas_region_window(terra::crs(x))
  }
  overlap <- terra::intersect(window, terra::ext(x))
  if (is.null(overlap)) {
    stop("this source does not cover North America", call. = FALSE)
  }
  terra::crop(x, overlap, snap = "out")
}

#' Put a raster onto a named grid: same projection, extent and cell size.
atlas_project_to_grid <- function(x, grid = "draft", method = "bilinear") {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed to build layers: install.packages('terra')", call. = FALSE)
  }
  terra::project(atlas_crop_to_region(x), atlas_grid_template(grid), method = method)
}

#' Build one layer onto a grid and record it.
atlas_build_layer <- function(id, grid = "draft", overwrite = FALSE, quiet = FALSE) {
  registry <- atlas_layer_registry()
  if (!id %in% names(registry)) {
    stop("unknown layer: ", id, ". Known: ", paste(names(registry), collapse = ", "),
         call. = FALSE)
  }
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed to build layers: install.packages('terra')", call. = FALSE)
  }
  entry <- registry[[id]]
  target <- atlas_layer_path(id, grid)

  if (file.exists(target) && !isTRUE(overwrite)) {
    if (!quiet) message("  ", id, ": already built (use --overwrite to rebuild)")
    return(invisible(NULL))
  }
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)

  if (!is.null(entry$derive)) {
    source_path <- atlas_layer_path(entry$depends, grid)
    if (!file.exists(source_path)) {
      stop(id, " is derived from ", entry$depends, ", which is not built yet",
           call. = FALSE)
    }
    if (!quiet) message("  ", id, ": deriving from ", entry$depends)
    built <- entry$derive(terra::rast(source_path))
  } else if (!is.null(entry$build)) {
    raw_dir <- atlas_path("layers", "raw", create = TRUE)
    dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
    if (!quiet) message("  ", id, ": building from ", entry$source)
    built <- entry$build(raw_dir, grid)
  } else {
    raw_dir <- atlas_path("layers", "raw", create = TRUE)
    dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
    if (!quiet) message("  ", id, ": fetching ", entry$source)
    raw <- entry$fetch(raw_dir, atlas_source_resolution(grid))
    if (!is.null(entry$rename)) {
      raw <- entry$rename(raw)
    }
    if (!quiet) message("  ", id, ": projecting ", terra::nlyr(raw), " band(s) onto the ", grid, " grid")
    built <- atlas_project_to_grid(raw, grid, entry$method)
  }

  if (!is.null(entry$supplement)) {
    if (!quiet) message("  ", id, ": filling where the source is silent, from the supplement")
    extra <- atlas_project_to_grid(entry$supplement(raw_dir, atlas_source_resolution(grid)),
                                   grid, entry$method)
    built <- atlas_supplement(built, extra, known = entry$supplement_known)
  }
  if (isTRUE(entry$fill_near)) {
    land <- atlas_land_mask(grid)
    if (is.null(land)) {
      stop(id, " is filled up to the land the land-cover layer knows: build landcover on the ",
           grid, " grid first", call. = FALSE)
    }
    built <- atlas_fill_near(built, land, max_km = ATLAS_FILL_NEAR_KM)
  }
  if (!is.null(entry$fill_outside)) {
    land_path <- atlas_layer_path("elevation", grid)
    if (!file.exists(land_path)) {
      stop(id, " is filled where its source is silent, up to the land the elevation ",
           "layer knows: build elevation on the ", grid, " grid first", call. = FALSE)
    }
    built <- atlas_fill_outside(built, terra::rast(land_path), known = entry$fill_outside,
                                flag = !isFALSE(entry$fill_flag))
  }

  terra::writeRaster(
    built, target, overwrite = TRUE,
    gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES", "BIGTIFF=IF_SAFER")
  )

  record <- list(
    id = entry$id,
    title = entry$title,
    grid = grid,
    bands = names(built),
    source = entry$source,
    url = entry$url,
    urls = if (is.null(entry$urls)) NULL else as.list(entry$urls),
    license = entry$license,
    citation = entry$citation,
    note = entry$note,
    method = entry$method,
    source_arcmin = if (is.null(entry$derive) && is.null(entry$build)) atlas_source_resolution(grid) else NA,
    cell_size_m = atlas_resolution(grid),
    file = basename(target),
    md5 = unname(tools::md5sum(target)),
    size_mb = round(file.info(target)$size / 1e6, 1),
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    terra_version = as.character(utils::packageVersion("terra"))
  )
  atlas_record_layer(record, grid)
  if (!quiet) {
    message("  ", id, ": ", length(record$bands), " band(s), ", record$size_mb, " MB")
  }
  invisible(record)
}

#' Fill a layer from a second source wherever the first is silent.
#'
#' A cell keeps the main source's values wherever it has all of them; where it
#' has none, it takes the supplement's; a band named known is 1 for the first
#' and 0 for the second, and empty where neither speaks.
atlas_supplement <- function(x, extra, known = "known") {
  bands <- names(x)
  extra <- terra::resample(extra, x, method = "near")
  names(extra) <- bands
  described <- !is.na(terra::app(x, "sum", na.rm = FALSE))
  supplied <- !described & !is.na(terra::app(extra, "sum", na.rm = FALSE))
  filled <- terra::ifel(described, x, extra)
  flag <- terra::ifel(described, 1, terra::ifel(supplied, 0, NA))
  out <- c(filled, flag)
  names(out) <- c(bands, known)
  out
}

# How far from a cell with data an empty land cell may be filled.
ATLAS_FILL_NEAR_KM <- 10

#' Where there is land on a grid: wherever the land-cover layer has data.
#' NULL when land cover is not built.
atlas_land_mask <- function(grid = "draft") {
  path <- atlas_layer_path("landcover", grid)
  if (!file.exists(path)) {
    return(NULL)
  }
  !is.na(terra::rast(path)[[1]])
}

#' Fill empty land cells from the cells around them.
#'
#' Each pass gives an empty cell the mean of its eight neighbours that have
#' data; a pass reaches one cell further, so as many passes are run as cells
#' fit in max_km. Cells that had data keep it exactly. Everything off the land
#' mask ends empty, whatever the passes put there, so the sea is not painted
#' with the coast's values.
atlas_fill_near <- function(x, land, max_km = ATLAS_FILL_NEAR_KM) {
  passes <- max(1L, as.integer(ceiling(max_km * 1000 / terra::res(x)[1])))
  filled <- x
  for (pass in seq_len(passes)) {
    empty_land <- terra::global(is.na(filled[[1]]) & land, "sum", na.rm = TRUE)[[1]]
    if (!is.finite(empty_land) || empty_land == 0) break
    filled <- terra::focal(filled, w = 3, fun = "mean", na.policy = "only", na.rm = TRUE)
  }
  out <- terra::mask(filled, land, maskvalues = c(FALSE, NA))
  names(out) <- names(x)
  out
}

#' Fill a layer where its source is silent but there is land.
#'
#' Cells the source describes keep their values and get known = 1. Land the
#' source does not reach gets 0 in every band and known = 0. The sea, where
#' land is NA, stays NA. Without this, one layer's gap removes that ground
#' from every model fitted on the grid, whether or not the model needs the
#' layer. flag = FALSE leaves the known band off, for a layer whose gaps
#' another layer's flag already names.
atlas_fill_outside <- function(x, land, known = "known", flag = TRUE) {
  bands <- names(x)
  land <- land[[1]]
  if (!terra::compareGeom(x, land, stopOnError = FALSE)) {
    x <- terra::extend(terra::crop(x, land), land)
  }
  # Known where every band has a value: a cell half described is not known.
  described <- !is.na(terra::app(x, "sum", na.rm = FALSE))
  filled <- terra::ifel(described, x, 0)
  if (!isTRUE(flag)) {
    out <- terra::mask(filled, land)
    names(out) <- bands
    return(out)
  }
  out <- terra::mask(c(filled, described * 1), land)
  names(out) <- c(bands, known)
  out
}

#' Build several layers, in an order that satisfies what they derive from.
atlas_build_layers <- function(ids = NULL, grid = "draft", overwrite = FALSE,
                               quiet = FALSE) {
  registry <- atlas_layer_registry()
  ids <- ids %||% names(registry)
  unknown <- setdiff(ids, names(registry))
  if (length(unknown)) {
    stop("unknown layer(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  derived <- vapply(registry[ids], function(x) !is.null(x$derive), logical(1))
  # Land cover first: the others are filled up to the land it knows.
  ordered <- c(intersect("landcover", ids), setdiff(ids[!derived], "landcover"), ids[derived])
  for (id in ordered) {
    atlas_build_layer(id, grid = grid, overwrite = overwrite, quiet = quiet)
  }
  invisible(atlas_layer_manifest(grid))
}

#' What is registered, and what of it is built.
atlas_layer_status <- function(grid = "draft") {
  registry <- atlas_layer_registry()
  manifest <- atlas_layer_manifest(grid)
  built <- vapply(manifest, function(x) as.character(x$id), character(1))
  data.frame(
    id = names(registry),
    title = vapply(registry, function(x) x$title, character(1)),
    built = names(registry) %in% built,
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

#' Every registered layer, with what is known about the built copy.
atlas_layer_overview <- function(grid = "draft") {
  registry <- atlas_layer_registry()
  manifest <- atlas_layer_manifest(grid)
  ids <- vapply(manifest, function(x) as.character(x$id), character(1))
  lapply(names(registry), function(id) {
    entry <- registry[[id]]
    record <- if (id %in% ids) manifest[[which(ids == id)[[1]]]] else NULL
    out <- list(
      id = id,
      title = entry$title,
      source = entry$source,
      # Derived layers have no download of their own.
      url = if (is.null(entry$url) || is.na(entry$url)) NULL else entry$url,
      license = entry$license,
      citation = entry$citation,
      note = entry$note,
      built = !is.null(record),
      # as.list keeps a one-band layer a JSON array rather than a bare string
      bands = if (is.null(record)) NULL else as.list(unlist(record$bands)),
      cellSizeM = if (is.null(record)) NULL else record$cell_size_m,
      sizeMb = if (is.null(record)) NULL else record$size_mb,
      builtAt = if (is.null(record)) NULL else record$built_at
    )
    Filter(Negate(is.null), out)
  })
}

`%||%` <- function(x, y) if (is.null(x)) y else x
