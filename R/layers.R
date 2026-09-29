# Environmental layers.
#
# Every layer must cover all of North America, because the grid does. That
# rules out the obvious United States products — TreeMap, NLCD, PAD-US stop at
# the lower 48, and British Columbia alone holds 8% of the records — so the
# registry uses global sources and accepts their coarser detail.
#
# The exceptions are the two host-tree layers (R/hosts.R, R/layersources.R).
# No continental map of tree species exists, so each joins a United States
# inventory to Canada's, and neither inventory speaks for Alaska, Hawaii,
# Puerto Rico or Mexico. A layer's gap must not take ground away from every
# model, so there the shares are filled with 0 and a band beside them
# (host_known, hostw_known) says the inventories were silent: the ground stays
# in every fit and on every map, and a model can tell "no such trees" from
# "nobody mapped the trees" (atlas_fill_outside).
#
# Layers after landcover are candidates, measured by atlas sweep-layers before
# any of them is fitted on in production (R/layersweep.R). Building a layer is
# what puts it into every fit on that grid, so candidates are built only into
# a separate data directory until they are chosen.

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
      method = "bilinear",
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
      method = "bilinear",
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
      method = "bilinear",
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
      title = "Soil pH, carbon, texture and exchange capacity (0-5 cm)",
      source = "SoilGrids 2.0",
      url = "https://soilgrids.org",
      license = "CC BY 4.0",
      citation = "Poggio L et al. (2021) SoilGrids 2.0. SOIL 7:217-240",
      method = "bilinear",
      # Downloaded rather than read remotely. SoilGrids' own service serves the
      # native 250 m grid — 58,034 x 159,246 cells in Interrupted Goode
      # Homolosine — and a continental window of that is a billion pixels to
      # pull over HTTP for a 5 km layer. geodata's pre-aggregated copy is the
      # right source for a grid this size.
      fetch = function(path, res) {
        vars <- c("phh2o", "soc", "clay", "sand", "cec")
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
      method = "bilinear",
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
    landform = list(
      id = "landform",
      title = "Wetness, northness and heat load",
      source = "Derived from the 1 km elevation layer",
      url = NA_character_,
      license = "Follows the elevation layer",
      citation = paste(
        "McCune B, Keon D (2002) Equations for potential annual direct incident",
        "radiation and heat load. J Veg Sci 13:603-606; wetness index after",
        "Beven KJ, Kirkby MJ (1979) Hydrol Sci Bull 24:43-69"
      ),
      # Averaged, not interpolated: a draft cell keeps the share of wet
      # hollows and shaded slopes its 1 km cells had. See R/landform.R.
      method = "average",
      fetch = function(path, res) atlas_landform_source(path)
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
      note = "Share of each cell under each forest type, counted from 30 m pixels.",
      method = "average",
      fetch = function(path, res) atlas_nalcms_source(path)
    ),
    hosts_wilson = list(
      id = "hosts_wilson",
      title = "Host tree genera from basal area 2000-2009 (share of the stand)",
      source = paste(
        "USFS live tree species basal area 2000-2009 (US lower 48);",
        "NFI kNN species composition 2011 (Canada)"
      ),
      url = "https://doi.org/10.2737/RDS-2013-0013",
      license = "US Government work; Open Government Licence - Canada",
      citation = paste(
        "Wilson BT, Lister AJ, Riemann RI, Griffith DM (2013) Live tree species basal",
        "area of the contiguous United States (2000-2009). USDA Forest Service,",
        "doi:10.2737/RDS-2013-0013; Beaudoin A et al. (2017) Species composition,",
        "forest properties and land cover types across Canada's forests at 250m",
        "resolution for 2001 and 2011. NRCan, doi:10.23687/ec9e2659-1c29-4ddb-87a2-6aced147a990"
      ),
      note = paste(
        "Two national products joined at the border: basal-area share in the US,",
        "stand-composition share in Canada. Alaska, Mexico and the islands are in",
        "neither: their shares are 0 and hostw_known is 0. An alternative to hosts,",
        "kept to be measured against it."
      ),
      fill_outside = "hostw_known",
      method = "average",
      fetch = function(path, res) atlas_hosts_wilson_source(path)
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
    ),
    bedrock = list(
      id = "bedrock",
      title = "Carbonate bedrock (share of the cell)",
      source = "GLiM global lithological map (Hartmann & Moosdorf 2012)",
      url = "https://www.geo.uni-hamburg.de/en/geologie/forschung/aquatische-geochemie/glim.html",
      license = "Not stated by the authors: confirm before publishing maps built on it",
      citation = paste(
        "Hartmann J, Moosdorf N (2012) The new global lithological map database GLiM.",
        "Geochem Geophys Geosyst 13:Q12004"
      ),
      method = "average",
      fetch = function(path, res) atlas_bedrock_source(path)
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

  if (!is.null(entry$fill_outside)) {
    land_path <- atlas_layer_path("elevation", grid)
    if (!file.exists(land_path)) {
      stop(id, " is filled where its source is silent, up to the land the elevation ",
           "layer knows: build elevation on the ", grid, " grid first", call. = FALSE)
    }
    built <- atlas_fill_outside(built, terra::rast(land_path), known = entry$fill_outside)
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

#' Fill a layer where its source is silent but there is land.
#'
#' Cells the source describes keep their values and get known = 1. Land the
#' source does not reach gets 0 in every band and known = 0. The sea, where
#' land is NA, stays NA. Without this, one layer's gap removes that ground
#' from every model fitted on the grid, whether or not the model needs the
#' layer.
atlas_fill_outside <- function(x, land, known = "known") {
  bands <- names(x)
  land <- land[[1]]
  if (!terra::compareGeom(x, land, stopOnError = FALSE)) {
    x <- terra::extend(terra::crop(x, land), land)
  }
  # Known where every band has a value: a cell half described is not known.
  described <- !is.na(terra::app(x, "sum", na.rm = FALSE))
  filled <- terra::ifel(described, x, 0)
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
  ordered <- c(ids[!derived], ids[derived])
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
