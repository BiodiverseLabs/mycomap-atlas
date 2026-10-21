# Draw web/public/og-card.png: the site's link-preview card, which Facebook,
# X, iMessage and Slack show for every Atlas page without a card of its own
# (web/index.html). 1200 x 630, in the same design as a species' card
# (R/card.R), with the words Steve chose on 2026-10-20 and a published
# habitat map.
#
# The map is the one atlas.mycomap.org shows for the taxon now (its best
# map, /api/taxa/<name>/best-map): the coloured overlay alone, which is
# already public. No collection, and no coordinate, is drawn. Run it again
# after a rebuild to refresh the picture:
#
#   Rscript tools/site-card.R                          # from the repo root
#   Rscript tools/site-card.R "Trametes ochracea" https://atlas.mycomap.org

args <- commandArgs(trailingOnly = TRUE)
taxon <- if (length(args) >= 1) args[[1]] else "Trametes ochracea"
origin <- if (length(args) >= 2) args[[2]] else "https://atlas.mycomap.org"

for (file in list.files("R", pattern = "[.][Rr]$", full.names = TRUE)) source(file)

best <- jsonlite::fromJSON(
  sprintf("%s/api/taxa/%s/best-map", origin, utils::URLencode(taxon, reserved = TRUE)),
  simplifyVector = FALSE
)
if (!isTRUE(best$available)) stop(taxon, " has no map to show: ", best$reason_text %||% "")
if (isTRUE(best$overlay$crosses_antimeridian)) stop(taxon, "'s map crosses the antimeridian; pick another")
overlay <- tempfile(fileext = ".png")
utils::download.file(best$overlay$url, overlay, mode = "wb", quiet = TRUE)

out <- file.path("web", "public", "og-card.png")
atlas_write_card_image(
  out, "Habitat maps for North America's fungi",
  lines = "Modelled only from DNA-validated MycoMap records",
  metrics = list(bounds = best$overlay$bounds, grade = best$choice$grade), overlay = overlay,
  caption = paste0(best$taxon, ", habitat suitability"), site = origin
)
message("wrote ", out, " from ", best$overlay$url)
