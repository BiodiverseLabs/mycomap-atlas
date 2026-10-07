# Readers for the layers that are not one download away through geodata.
#
# Each turns a source into a raster that atlas_build_layer can project onto a
# grid, and keeps its result beside the raw download, so the draft and the
# production grid are both built from one pass over the source. The sources
# are large (the land cover alone is 66 billion cells), so each is reduced to
# roughly 1 km once, as fractions or shares, and every grid is averaged from
# that.
#
# Downloads are fetched by URL into the raw directory the first time and
# reused after that. The URLs and what each file is are in ATLAS_SOURCE_FILES.

ATLAS_SOURCE_FILES <- list(
  nalcms = list(
    url = paste0("https://www.cec.org/files/atlas_layers/1_terrestrial_ecosystems/",
                 "1_01_0_land_cover_2020_30m/land_cover_2020v2_30m_tif.zip"),
    member = paste0("land_cover_2020v2_30m_tif/NA_NALCMS_landcover_2020v2_30m/data/",
                    "NA_NALCMS_landcover_2020v2_30m.tif")
  ),
  adaptwest = list(
    url = paste0("https://s3-us-west-2.amazonaws.com/www.cacpd.org/CMIP6v73/normals/",
                 "Normal_1991_2020_bioclim.zip")
  ),
  terraclimate = list(
    url = paste0("https://thredds.northwestknowledge.net/thredds/fileServer/",
                 "TERRACLIMATE_ALL/climatology/TerraClimate_19912020_%s.nc")
  )
)

#' Fetch a URL into a file once; a file already there is reused.
atlas_fetch_once <- function(url, path) {
  if (file.exists(path) && file.info(path)$size > 0) {
    return(path)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  partial <- paste0(path, ".part")
  utils::download.file(url, partial, mode = "wb", quiet = TRUE)
  file.rename(partial, path)
  path
}

#' Write a raster beside the raw downloads, compressed and tiled.
atlas_write_cached <- function(x, path) {
  atlas_write_raster_whole(x, path, gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER"))
  terra::rast(path)
}

#' Write a raster that a later run will trust because it exists.
#'
#' Every raw cache here is reused on sight, so a write that dies halfway (out
#' of memory, a full disk) must not leave a file at the cache's own path: the
#' next run would read the stub as the cache, or fail on it. The raster is
#' written to <path>.part and renamed into place only once the write returns;
#' a .part left behind is never read, and the next write replaces it.
atlas_write_raster_whole <- function(x, path, gdal = c("COMPRESS=DEFLATE")) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  part <- paste0(path, ".part")
  unlink(part)
  ok <- FALSE
  on.exit(if (!ok) unlink(part), add = TRUE)
  terra::writeRaster(x, part, filetype = "GTiff", overwrite = TRUE, gdal = gdal)
  if (file.exists(path)) unlink(path)
  if (!file.rename(part, path)) {
    stop("could not move ", basename(part), " into place", call. = FALSE)
  }
  ok <- TRUE
  invisible(path)
}

# ---- Forest type: NALCMS 2020 ------------------------------------------------

# NALCMS classes grouped by leaf type. Taiga (2) is needleleaf forest too; the
# two tropical broadleaf classes (3, 4) matter only in Mexico. Mixed (6) is its
# own group: a mycologist reads "mixed wood" as a habitat, not as half of each.
ATLAS_NALCMS_GROUPS <- list(
  forest_needleleaf = c(1L, 2L),
  forest_broadleaf = c(3L, 4L, 5L),
  forest_mixed = 6L
)

#' A VRT that reads the class raster as one 0/1 band per forest group.
#'
#' A lookup table in the VRT does the classifying as pixels stream through, so
#' averaging 66 billion cells down to 1 km never writes an intermediate copy.
#' Class 0 is outside the survey and is read as missing, not as "not forest".
atlas_nalcms_vrt <- function(class_tif, path, groups = ATLAS_NALCMS_GROUPS) {
  info <- terra::rast(class_tif)
  lut <- function(codes) {
    values <- vapply(0:19, function(k) if (k %in% codes) 1L else 0L, integer(1))
    paste(sprintf("%d:%d", 0:19, values), collapse = ",")
  }
  source <- normalizePath(class_tif, winslash = "/")
  bands <- vapply(seq_along(groups), function(i) {
    paste0(
      '  <VRTRasterBand dataType="Byte" band="', i, '">\n',
      '    <Description>', names(groups)[[i]], '</Description>\n',
      '    <NoDataValue>255</NoDataValue>\n',
      '    <ComplexSource>\n',
      '      <SourceFilename relativeToVRT="0">', source, '</SourceFilename>\n',
      '      <SourceBand>1</SourceBand>\n',
      '      <NODATA>0</NODATA>\n',
      '      <LUT>', lut(groups[[i]]), '</LUT>\n',
      '    </ComplexSource>\n',
      '  </VRTRasterBand>\n'
    )
  }, character(1))
  e <- terra::ext(info)
  gt <- c(e[1], terra::res(info)[1], 0, e[4], 0, -terra::res(info)[2])
  xml <- paste0(
    '<VRTDataset rasterXSize="', terra::ncol(info), '" rasterYSize="', terra::nrow(info), '">\n',
    '  <SRS>', gsub("&", "&amp;", gsub("<", "&lt;", terra::crs(info))), '</SRS>\n',
    '  <GeoTransform>', paste(format(gt, scientific = FALSE, digits = 15), collapse = ", "),
    '</GeoTransform>\n',
    paste(bands, collapse = ""),
    '</VRTDataset>\n'
  )
  writeLines(xml, path)
  path
}

#' Share of each ~1 km cell under needleleaf, broadleaf and mixed forest.
atlas_nalcms_source <- function(raw_dir, fact = 33L) {
  cached <- file.path(raw_dir, "nalcms", "forest-fractions-1km.tif")
  if (file.exists(cached)) {
    return(terra::rast(cached))
  }
  dir <- file.path(raw_dir, "nalcms")
  class_tif <- file.path(dir, basename(ATLAS_SOURCE_FILES$nalcms$member))
  if (!file.exists(class_tif)) {
    zip <- atlas_fetch_once(ATLAS_SOURCE_FILES$nalcms$url,
                            file.path(dir, basename(ATLAS_SOURCE_FILES$nalcms$url)))
    # Only the class raster: its .ovr overviews are sampled, not averaged,
    # and a warp that found them would read fractions off a thinned image.
    utils::unzip(zip, files = ATLAS_SOURCE_FILES$nalcms$member, exdir = dir, junkpaths = TRUE)
  }
  vrt <- atlas_nalcms_vrt(class_tif, file.path(dir, "forest-groups.vrt"))
  groups <- terra::rast(vrt)
  out <- terra::aggregate(groups, fact = fact, fun = "mean", na.rm = TRUE)
  names(out) <- names(ATLAS_NALCMS_GROUPS)
  atlas_write_cached(out, cached)
}

# ---- Forest type where NALCMS is silent: Copernicus Global Land Cover -------
#
# NALCMS has nothing for Hawaii or the Caribbean islands, which hold about
# 1,700 records. Copernicus Global Land Cover (100 m, 2019, CC BY 4.0) covers
# the globe and splits forest the same three ways, so it fills whatever NALCMS
# leaves empty. Only the windows NALCMS misses are read from the 1.6 GB file.

ATLAS_COPERNICUS_FILE <- "PROBAV_LC100_global_v3.0.1_2019-nrt_Discrete-Classification-map_EPSG-4326.tif"
ATLAS_COPERNICUS_URL <- paste0("https://zenodo.org/api/records/3939050/files/",
                               ATLAS_COPERNICUS_FILE, "/content")

# Copernicus discrete classes by leaf type: closed (11x) and open (12x)
# forest, evergreen and deciduous. Forest of unknown type (116, 126) counts
# for none of the three, as NALCMS's own "unknown" would.
ATLAS_COPERNICUS_GROUPS <- list(
  forest_needleleaf = c(111L, 113L, 121L, 123L),
  forest_broadleaf = c(112L, 114L, 122L, 124L),
  forest_mixed = c(115L, 125L)
)

# Where NALCMS is silent and there are records: Hawaii, and the Caribbean
# from the Bahamas to Trinidad. Longitude and latitude.
ATLAS_COPERNICUS_WINDOWS <- list(
  hawaii = c(xmin = -161, xmax = -154, ymin = 18.5, ymax = 22.5),
  caribbean = c(xmin = -85.5, xmax = -59, ymin = 10, ymax = 27.5)
)

#' Forest fractions from a window of a Copernicus class raster: one 0/1
#' band per group, averaged by fact (100 m to 1 km is 10).
atlas_copernicus_fractions <- function(classes, fact = 10L, groups = ATLAS_COPERNICUS_GROUPS) {
  bands <- lapply(groups, function(codes) {
    terra::ifel(is.na(classes), NA, as.numeric(terra::`%in%`(classes, codes)))
  })
  out <- terra::rast(bands)
  # Copernicus's 0 is "no input data", not a class: read it as missing.
  out <- terra::mask(out, classes, maskvalues = 0)
  if (fact > 1L) out <- terra::aggregate(out, fact = fact, fun = "mean", na.rm = TRUE)
  names(out) <- names(groups)
  out
}

#' Copernicus forest fractions at 1 km over the windows NALCMS misses, as a
#' collection of one raster per window.
atlas_copernicus_source <- function(raw_dir, windows = ATLAS_COPERNICUS_WINDOWS) {
  cached <- file.path(raw_dir, "copernicus", "forest-fractions-1km.tif")
  if (file.exists(cached)) {
    return(terra::rast(cached))
  }
  path <- atlas_fetch_once(ATLAS_COPERNICUS_URL, file.path(raw_dir, "copernicus", ATLAS_COPERNICUS_FILE))
  classes <- terra::rast(path)
  parts <- lapply(windows, function(w) {
    atlas_copernicus_fractions(terra::crop(classes, terra::ext(w[["xmin"]], w[["xmax"]],
                                                                 w[["ymin"]], w[["ymax"]])))
  })
  out <- if (length(parts) == 1L) parts[[1]] else terra::merge(terra::sprc(parts))
  names(out) <- names(ATLAS_COPERNICUS_GROUPS)
  atlas_write_cached(out, cached)
}

# ---- Climate 1991-2020: AdaptWest (ClimateNA) --------------------------------

# The rest of ClimateNA's 1991-2020 normals: everything the water-balance layer
# below does not already carry. Together the two replace WorldClim's
# 1970-2000 bioclim with the climate of the years the records were collected.
ATLAS_CLIMATENA_CORE_VARS <- c(
  MAT = "cna_mat",       # mean annual temperature, C
  MWMT = "cna_mwmt",     # mean warmest-month temperature, C
  MCMT = "cna_mcmt",     # mean coldest-month temperature, C
  TD = "cna_td",         # continentality: MWMT - MCMT, C
  MAP = "cna_map",       # mean annual precipitation, mm
  MSP = "cna_msp",       # May-September precipitation, mm
  AHM = "cna_ahm",       # annual heat-moisture index
  SHM = "cna_shm",       # summer heat-moisture index
  CMI = "cna_cmi",       # Hogg's climate moisture index, cm
  DD5 = "cna_dd5",       # degree-days above 5 C (growing warmth)
  DD_0 = "cna_dd0",      # degree-days below 0 C (winter cold)
  NFFD = "cna_nffd",     # number of frost-free days
  EMT = "cna_emt",       # extreme minimum temperature over 30 years, C
  EXT = "cna_ext",       # extreme maximum temperature over 30 years, C
  Eref = "cna_eref",     # Hargreaves reference evaporation, mm
  PPT_wt = "cna_ppt_winter", PPT_sp = "cna_ppt_spring", PPT_sm = "cna_ppt_summer",
  Tave_wt = "cna_tave_winter", Tave_sp = "cna_tave_spring", Tave_sm = "cna_tave_summer"
)

#' ClimateNA's 1991-2020 temperature, precipitation and heat-moisture
#' normals, on ClimateNA's 1 km grid. ClimateNA covers the continent, Mexico
#' included, but not Hawaii or the Caribbean islands.
atlas_climatena_source <- function(raw_dir) {
  cached <- file.path(raw_dir, "climatena", "climatena-1km.tif")
  if (file.exists(cached)) {
    return(terra::rast(cached))
  }
  aw_dir <- file.path(raw_dir, "adaptwest")
  folder <- file.path(aw_dir, "Normal_1991_2020_bioclim")
  if (!dir.exists(folder)) {
    zip <- atlas_fetch_once(ATLAS_SOURCE_FILES$adaptwest$url,
                            file.path(aw_dir, basename(ATLAS_SOURCE_FILES$adaptwest$url)))
    utils::unzip(zip, exdir = aw_dir)
  }
  out <- terra::rast(file.path(
    folder, paste0("Normal_1991_2020_", names(ATLAS_CLIMATENA_CORE_VARS), ".tif")
  ))
  names(out) <- unname(ATLAS_CLIMATENA_CORE_VARS)
  atlas_write_cached(out, cached)
}

# ---- Water balance: AdaptWest (ClimateNA) and TerraClimate ------------------

# ClimateNA 1991-2020 normals, and the name each takes as a predictor.
ATLAS_CLIMATENA_VARS <- c(
  CMD = "clim_cmd",           # Hargreaves climatic moisture deficit, mm
  PPT_at = "clim_ppt_autumn", # autumn (Sep-Nov) precipitation, mm
  Tave_at = "clim_tave_autumn", # autumn mean temperature, C
  FFP = "clim_ffp",           # frost-free period, days
  PAS = "clim_pas",           # precipitation as snow, mm
  RH = "clim_rh"              # mean annual relative humidity, %
)

#' ClimateNA moisture and season variables with TerraClimate's actual
#' evapotranspiration and vapour pressure deficit, on ClimateNA's 1 km grid.
atlas_waterbalance_source <- function(raw_dir) {
  cached <- file.path(raw_dir, "waterbalance", "waterbalance-1km.tif")
  if (file.exists(cached)) {
    return(terra::rast(cached))
  }
  aw_dir <- file.path(raw_dir, "adaptwest")
  folder <- file.path(aw_dir, "Normal_1991_2020_bioclim")
  if (!dir.exists(folder)) {
    zip <- atlas_fetch_once(ATLAS_SOURCE_FILES$adaptwest$url,
                            file.path(aw_dir, basename(ATLAS_SOURCE_FILES$adaptwest$url)))
    utils::unzip(zip, exdir = aw_dir)
  }
  climatena <- terra::rast(file.path(
    folder, paste0("Normal_1991_2020_", names(ATLAS_CLIMATENA_VARS), ".tif")
  ))
  names(climatena) <- unname(ATLAS_CLIMATENA_VARS)

  tc <- function(var, summarise) {
    path <- atlas_fetch_once(
      sprintf(ATLAS_SOURCE_FILES$terraclimate$url, var),
      file.path(raw_dir, "terraclimate", sprintf("TerraClimate_19912020_%s.nc", var))
    )
    months <- atlas_crop_to_region(terra::rast(path))
    yearly <- summarise(months)
    terra::project(yearly, climatena, method = "bilinear")
  }
  aet <- tc("aet", function(m) terra::app(m, "sum"))   # mm a year
  vpd <- tc("vpd", function(m) terra::app(m, "mean"))  # kPa, the mean month
  out <- c(climatena, aet, vpd)
  names(out) <- c(unname(ATLAS_CLIMATENA_VARS), "clim_aet", "clim_vpd")
  # TerraClimate covers the sea's edge a little differently from ClimateNA:
  # keep only land both describe.
  out <- terra::mask(out, climatena[[1]])
  atlas_write_cached(out, cached)
}
