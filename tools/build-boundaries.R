# Build inst/boundaries/ from Natural Earth (public domain).
#
# Atlas needs state and province outlines for three things: which states a
# species' map rates highly, and the map image drawn for spreadsheets and
# slides, with country outlines and lakes behind it. Natural Earth covers the
# United States, Canada and Mexico alike, where the Census file in R/hosts.R
# covers only the United States.
#
# The files are cut to North America, simplified to about 2 km and rounded,
# so the committed copies stay small. Run it again to change them, from the
# zips below (version 5.1.1, checked against the hashes):
#
#   Rscript tools/build-boundaries.R <folder holding the three zips>   # from the repo root

ZIPS <- c(
  ne_10m_admin_1_states_provinces = "efc59726337323058f9446210adc96673179cd344e053666ee3d28cb58ba2b05",
  ne_50m_admin_0_countries = "5fed433373581fa648920435f937d95f2d3c0200e067409c6478dcdf1b853139",
  ne_50m_lakes = "f28d42c286d96b57a17aac2cbeb432f8c65532c20063495711fbc64e24666df3"
)
# From https://naciscdn.org/naturalearth/{10m,50m}/{cultural,physical}/<name>.zip

# West of -180 is the far Aleutians, left out; 5N takes in Central America.
BOX <- c(xmin = -180, xmax = -50, ymin = 5, ymax = 84)
TOLERANCE <- 0.02

args <- commandArgs(trailingOnly = TRUE)
folder <- if (length(args)) args[[1]] else stop("give the folder holding the zips")
root <- normalizePath(".")
if (!file.exists(file.path(root, "DESCRIPTION"))) stop("run this from the repository root")
for (file in list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) source(file)

read_zip <- function(name) {
  zip <- file.path(folder, paste0(name, ".zip"))
  if (digest::digest(file = zip, algo = "sha256") != ZIPS[[name]]) stop(zip, " is not the pinned version")
  out <- file.path(tempdir(), name)
  utils::unzip(zip, exdir = out)
  terra::vect(file.path(out, paste0(name, ".shp")))
}

cut <- function(v) {
  v <- terra::crop(terra::makeValid(v), terra::ext(BOX))
  terra::simplifyGeom(v, tolerance = TOLERANCE, preserveTopology = TRUE)
}

write <- function(v, name) {
  dir.create(file.path(root, "inst", "boundaries"), recursive = TRUE, showWarnings = FALSE)
  path <- file.path(root, "inst", "boundaries", paste0(name, ".geojson"))
  unlink(path)
  terra::writeVector(v, path, filetype = "GeoJSON",
                     options = c("COORDINATE_PRECISION=3", "RFC7946=NO", "WRITE_BBOX=NO"))
  message(name, ": ", nrow(v), " features, ", round(file.size(path) / 1024), " KB")
}

# States, provinces and territories, coded as R/regions.R codes them.
admin1 <- read_zip("ne_10m_admin_1_states_provinces")
admin1 <- admin1[admin1$adm0_a3 %in% c("USA", "CAN", "MEX", "PRI", "VIR"), ]
code <- admin1$iso_3166_2
code[startsWith(code, "VI-")] <- "US-VI"   # the three islands, as one territory
code[code == "MX-DIF"] <- "MX-CMX"          # Mexico City's code since 2016
admin1$code <- code
known <- vapply(atlas_region_list(), `[[`, "", "code")
admin1 <- admin1[admin1$code %in% known, "code"]
admin1 <- terra::aggregate(admin1, by = "code")
admin1 <- admin1[, "code"]
missing <- setdiff(known, admin1$code)
if (length(missing)) stop("no outline for: ", paste(missing, collapse = ", "))
write(cut(admin1), "regions")

# Countries, for land behind the map.
countries <- read_zip("ne_50m_admin_0_countries")
countries$code <- countries$ADM0_A3
write(cut(countries[, "code"]), "countries")

# Lakes big enough to read on a continental map.
lakes <- read_zip("ne_50m_lakes")
lakes <- lakes[lakes$scalerank <= 2, ]
write(cut(lakes[, "name"]), "lakes")
