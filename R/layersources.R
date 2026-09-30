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
  ),
  wilson = list(
    url = "https://www.fs.usda.gov/rds/archive/products/RDS-2013-0013/%s",
    files = c("RDS-2013-0013_Data.zip", "RDS-2013-0013_RasterMaps_s10-s350.zip",
              "RDS-2013-0013_RasterMaps_s351-s600.zip",
              "RDS-2013-0013_RasterMaps_s601-s825.zip",
              "RDS-2013-0013_RasterMaps_s826-s999.zip")
  ),
  knn = list(
    url = paste0("https://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/",
                 "canada-forests-attributes_attributs-forests-canada/",
                 "2011-attributes_attributs-2011/",
                 "NFI_MODIS250m_2011_kNN_Species_%s_v1.tif")
  ),
  glim = list(
    url = "https://www.dropbox.com/s/9vuowtebp9f1iud/LiMW_GIS%202015.gdb.zip?dl=1",
    file = "LiMW_GIS_2015.gdb.zip",
    gdb = "LiMW_GIS 2015.gdb"
  )
)

# Canada's kNN layers use a Lambert Conformal Conic whose latitude of origin
# is 0, which is not EPSG:3978 (origin 49). The files say so in a form GDAL
# reads correctly, but a PROJ string is kept here to check against.
ATLAS_KNN_CRS <- "+proj=lcc +lat_0=0 +lon_0=-95 +lat_1=49 +lat_2=77 +datum=NAD83 +units=m +no_defs"

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
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(x, path, overwrite = TRUE,
                     gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER"))
  terra::rast(path)
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

# ---- Host trees: USFS basal area (US) and NFI kNN (Canada) ------------------

# The alternative host layer (hosts_wilson, bands hostw_*), kept to be measured
# against R/hosts.R's. Host genera and the Canadian kNN file codes that make up each. "<Genus>_Spp"
# is the kNN's unidentified-species class, not the genus total, so the total
# is that plus every named species.
ATLAS_WILSON_GENERA <- list(
  Pinus = c("Pinu_Spp", "Pinu_Alb", "Pinu_Ban", "Pinu_Con", "Pinu_Mon",
            "Pinu_Pon", "Pinu_Res", "Pinu_Str", "Pinu_Syl"),
  Picea = c("Pice_Spp", "Pice_Abi", "Pice_Eng", "Pice_Gla", "Pice_Mar",
            "Pice_Rub", "Pice_Sit"),
  Abies = c("Abie_Spp", "Abie_Ama", "Abie_Bal", "Abie_Las"),
  Tsuga = c("Tsug_Spp", "Tsug_Can", "Tsug_Het", "Tsug_Mer"),
  Pseudotsuga = "Pseu_Men",
  Larix = c("Lari_Spp", "Lari_Lar", "Lari_Lya", "Lari_Occ"),
  Quercus = c("Quer_Spp", "Quer_Alb", "Quer_Mac", "Quer_Rub"),
  Fagus = "Fagu_Gra",
  Betula = c("Betu_Spp", "Betu_All", "Betu_Pap", "Betu_Pop"),
  Populus = c("Popu_Spp", "Popu_Bal", "Popu_Gra", "Popu_Tre", "Popu_Tri")
)

#' The predictor name for a host genus.
atlas_wilson_band <- function(genus) paste0("hostw_", tolower(genus))

#' FIA species codes of the US rasters, with the genus each belongs to.
atlas_wilson_species <- function(data_zip) {
  atlas_parse_wilson_species(
    readLines(unz(data_zip, "Data/agreement_metrics_200k.csv"), warn = FALSE)
  )
}

#' The species table's lines as code and genus.
#'
#' Read by position, not by header: every data row ends in a comma, one field
#' more than the header, and read.csv answers that by turning the first
#' column into row names and shifting every other column one to the left.
atlas_parse_wilson_species <- function(lines) {
  table <- utils::read.csv(text = lines[-1], header = FALSE, stringsAsFactors = FALSE,
                           colClasses = "character")
  header <- trimws(strsplit(lines[[1]], ",", fixed = TRUE)[[1]])
  code_col <- which(header == "Spp code")
  name_col <- which(header == "Scientific Name")
  if (length(code_col) != 1L || length(name_col) != 1L) {
    stop("the USFS species table has no 'Spp code' / 'Scientific Name' columns", call. = FALSE)
  }
  data.frame(
    code = as.integer(table[[code_col]]),
    genus = sub(" .*$", "", trimws(table[[name_col]])),
    stringsAsFactors = FALSE
  )
}

#' Share of live-tree basal area in each host genus, US lower 48, at 1 km.
#'
#' Share, not basal area, because Canada's layers are shares of the stand and
#' the two must meet at the border in the same unit. Non-forest is 0.
atlas_wilson_shares <- function(raw_dir, fact = 4L) {
  dir <- file.path(raw_dir, "wilson")
  zips <- vapply(ATLAS_SOURCE_FILES$wilson$files, function(f) {
    atlas_fetch_once(sprintf(ATLAS_SOURCE_FILES$wilson$url, f), file.path(dir, f))
  }, character(1))
  maps <- file.path(dir, "Data", "RasterMaps")
  if (!dir.exists(maps)) {
    for (zip in zips[-1]) utils::unzip(zip, exdir = dir)
  }
  species <- atlas_wilson_species(zips[[1]])
  files <- file.path(maps, paste0("s", species$code, ".img"))
  atlas_basal_area_shares(files[file.exists(files)], species$genus[file.exists(files)],
                          fact = fact)
}

#' Genus shares of total basal area, from one basal-area raster per species.
#'
#' files and genus run in parallel: genus[i] is the genus of files[i]. The
#' total is every species, host or not. Where there are no trees the share
#' is 0; outside the rasters' coverage it stays missing.
atlas_basal_area_shares <- function(files, genus, genera = names(ATLAS_WILSON_GENERA),
                                    fact = 4L) {
  coarse <- function(paths) {
    total <- terra::app(terra::rast(paths), "sum", na.rm = TRUE)
    if (fact > 1L) total <- terra::aggregate(total, fact = fact, fun = "mean", na.rm = TRUE)
    total
  }
  all_trees <- coarse(files)
  shares <- lapply(genera, function(g) {
    genus_files <- files[genus == g]
    if (!length(genus_files)) {
      return(all_trees * 0)
    }
    terra::ifel(all_trees > 0, coarse(genus_files) / all_trees, 0)
  })
  out <- terra::rast(shares)
  names(out) <- atlas_wilson_band(genera)
  out
}

#' Share of the stand in each host genus, Canada, at 1 km.
atlas_knn_shares <- function(raw_dir, fact = 4L) {
  dir <- file.path(raw_dir, "knn")
  paths <- lapply(ATLAS_WILSON_GENERA, function(codes) {
    vapply(codes, function(code) {
      atlas_fetch_once(sprintf(ATLAS_SOURCE_FILES$knn$url, code),
                       file.path(dir, basename(sprintf(ATLAS_SOURCE_FILES$knn$url, code))))
    }, character(1))
  })
  atlas_composition_shares(paths, fact = fact)
}

#' Genus shares from percent-composition rasters: a named list, genus ->
#' the files of every class in it (the unidentified class and each species),
#' which are summed.
atlas_composition_shares <- function(paths, fact = 4L) {
  shares <- lapply(paths, function(files) {
    percent <- terra::app(terra::rast(files), "sum", na.rm = TRUE)
    share <- percent / 100
    if (fact > 1L) share <- terra::aggregate(share, fact = fact, fun = "mean", na.rm = TRUE)
    share
  })
  out <- terra::rast(shares)
  names(out) <- atlas_wilson_band(names(paths))
  out
}

#' US and Canadian genus shares on the 1 km production grid, as one layer.
#'
#' Where both describe a cell, along the border, the two are averaged.
#' Alaska, Mexico and the islands are covered by neither and stay missing.
atlas_hosts_wilson_source <- function(raw_dir) {
  cached <- file.path(raw_dir, "hosts", "hosts-1km.tif")
  if (file.exists(cached)) {
    # A cache written before this layer had its own band names says host_.
    out <- terra::rast(cached)
    names(out) <- atlas_wilson_band(names(ATLAS_WILSON_GENERA))
    return(out)
  }
  template <- atlas_grid_template("production")
  us <- terra::project(atlas_wilson_shares(raw_dir), template, method = "average")
  ca <- terra::project(atlas_knn_shares(raw_dir), template, method = "average")
  out <- terra::mosaic(terra::sprc(list(us, ca)), fun = "mean")
  names(out) <- atlas_wilson_band(names(ATLAS_WILSON_GENERA))
  atlas_write_cached(out, cached)
}

# ---- Bedrock: GLiM carbonate rocks -------------------------------------------

#' Share of each 1 km production cell underlain by carbonate sedimentary rock.
#'
#' GLiM's first-level class "sc". Evaporites and mixed sedimentary rocks are
#' left out: mixed rocks are mostly siliciclastic, and the question the layer
#' answers is lime or no lime. Land GLiM does not map as carbonate is 0; the
#' sea is masked by the production elevation layer.
atlas_bedrock_source <- function(raw_dir) {
  cached <- file.path(raw_dir, "bedrock", "carbonate-1km.tif")
  if (file.exists(cached)) {
    return(terra::rast(cached))
  }
  dir <- file.path(raw_dir, "glim")
  gdb <- file.path(dir, ATLAS_SOURCE_FILES$glim$gdb)
  if (!dir.exists(gdb)) {
    zip <- atlas_fetch_once(ATLAS_SOURCE_FILES$glim$url, file.path(dir, ATLAS_SOURCE_FILES$glim$file))
    utils::unzip(zip, exdir = dir)
  }
  elevation_path <- atlas_layer_path("elevation", "production")
  if (!file.exists(elevation_path)) {
    stop("bedrock is masked to land by the production elevation layer: ",
         "run atlas build-layers --grid=production --only=elevation first", call. = FALSE)
  }
  window <- atlas_region_window("ESRI:54012")
  rocks <- terra::vect(gdb, layer = "GLiM_export", extent = window,
                       query = "SELECT xx FROM GLiM_export WHERE xx = 'sc'")
  out <- atlas_carbonate_cover(rocks, terra::rast(elevation_path))
  atlas_write_cached(out, cached)
}

#' Share of each cell of land covered by the given rock polygons.
atlas_carbonate_cover <- function(rocks, land) {
  rocks <- terra::project(rocks, terra::crs(land))
  cover <- terra::rasterize(rocks, land, cover = TRUE, background = 0)
  out <- terra::mask(cover, land)
  names(out) <- "bedrock_carbonate"
  out
}
