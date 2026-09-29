# Environmental layers.
#
# Every layer must cover all of North America, because the grid does. That
# rules out the obvious United States products — TreeMap, NLCD, PAD-US stop at
# the lower 48, and British Columbia alone holds 8% of the records — so the
# registry uses global sources and accepts their coarser detail.
#
# The one exception is the host-tree layer (R/hosts.R). No continental map of
# tree species exists, so it joins the two national forest inventories, the
# United States' and Canada's, and leaves Alaska, Hawaii, Puerto Rico and
# Mexico empty: those records drop out of fitting, a price paid for knowing
# which trees grow where across the rest.

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
        "Lower 48 and Canada only: Alaska, Hawaii, Puerto Rico and Mexico have no tree",
        "inventory here, are empty, and are not modelled."
      ),
      # Built on the grid directly, not fetched and reprojected: BIGMAP is read
      # in the grid's own projection, and both inventories need summing by
      # genus before anything is averaged.
      build = function(raw_dir, grid) atlas_build_hosts(raw_dir, grid)
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
