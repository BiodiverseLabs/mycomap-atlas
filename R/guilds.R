# Fungal guilds, for ordering predictors.
#
# Which trees grow in a place matters most to a fungus that lives on their
# roots. So Maxent's predictor order (R/predictors.R) depends on the guild:
# for an ectomycorrhizal fungus the host bands come straight after soil pH,
# for anything else after the climate block. The guild is looked up by genus
# in FungalTraits (Põlme et al. 2020), whose genus table is the standard
# lifestyle reference for fungi.
#
# FungalTraits' licence is unclear, so it is used for lookup only: the table
# is fetched into the data directory (./atlas fetch-guilds), never committed,
# never put in a release, never served. Without it every taxon's guild is
# "unknown" and the ordering falls back to the one for non-mycorrhizal fungi.

ATLAS_FUNGALTRAITS_URL <- paste0(
  "https://raw.githubusercontent.com/globalbioticinteractions/fungaltraits/",
  "main/polme2020-s1-fungal-traits-genera.csv"
)

ATLAS_GUILD_UNKNOWN <- "unknown"

#' Where the FungalTraits genus table is kept.
atlas_guild_table_path <- function() {
  atlas_path("reference", "fungaltraits-genera.csv")
}

#' Download the FungalTraits genus table into the data directory.
atlas_fetch_guild_table <- function(url = ATLAS_FUNGALTRAITS_URL, http = atlas_host_http,
                                    quiet = FALSE) {
  dest <- atlas_guild_table_path()
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  atlas_fetch_file(url, dest, http = http, check = function(path) {
    header <- readLines(path, n = 1L, warn = FALSE)
    length(header) == 1L && grepl("GENUS", header, fixed = TRUE) &&
      grepl("primary_lifestyle", header, fixed = TRUE)
  })
  guilds <- atlas_read_guild_table(dest)
  if (!quiet) {
    message("FungalTraits: ", length(guilds), " genera with a lifestyle, ",
            sum(guilds == "ectomycorrhizal"), " ectomycorrhizal")
    message("  written: ", dest, " (lookup only; never committed or published)")
  }
  invisible(dest)
}

#' The genus table as a named vector, genus -> primary lifestyle.
#'
#' Genera with no lifestyle recorded are left out, so they read as unknown. A
#' genus name listed twice with different lifestyles is a homonym — two
#' unrelated fungi sharing a name — and is left out too rather than guessed.
atlas_read_guild_table <- function(path = atlas_guild_table_path()) {
  if (!file.exists(path)) {
    return(stats::setNames(character(), character()))
  }
  table <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                           encoding = "UTF-8", na.strings = c("", "NA"))
  if (!all(c("GENUS", "primary_lifestyle") %in% names(table))) {
    stop("not a FungalTraits genus table: ", path, call. = FALSE)
  }
  genus <- trimws(table$GENUS)
  lifestyle <- tolower(trimws(table$primary_lifestyle))
  keep <- !is.na(genus) & nzchar(genus) & !is.na(lifestyle) & nzchar(lifestyle)
  genus <- genus[keep]
  lifestyle <- lifestyle[keep]
  agreed <- tapply(lifestyle, genus, function(x) if (length(unique(x)) == 1L) x[[1]] else NA_character_)
  agreed <- agreed[!is.na(agreed)]
  stats::setNames(as.character(agreed), names(agreed))
}

# Read once per process and file version: a batch looks up hundreds of taxa.
atlas_guild_cache <- new.env(parent = emptyenv())

#' The guild table, read at most once while the file is unchanged.
atlas_guild_table <- function(path = atlas_guild_table_path()) {
  stamp <- if (file.exists(path)) paste(path, file.info(path)$size, file.info(path)$mtime) else paste(path, "absent")
  if (!identical(atlas_guild_cache$stamp, stamp)) {
    atlas_guild_cache$table <- atlas_read_guild_table(path)
    atlas_guild_cache$stamp <- stamp
  }
  atlas_guild_cache$table
}

#' The genus a scientific name belongs to: its first word.
#'
#' Provisional names still begin with the genus ("Mycena sp. 'IN10'"), and so
#' do names with a section or a variety. A first word that is not a Latin
#' genus — a bare code, a quoted placeholder — has no genus.
atlas_taxon_genus <- function(name) {
  first <- sub("[[:space:]].*$", "", trimws(as.character(name)))
  ok <- !is.na(first) & grepl("^[A-Z][a-z-]+$", first)
  ifelse(ok, first, NA_character_)
}

#' The guild of a taxon, from its genus: the FungalTraits primary lifestyle,
#' or "unknown" when the genus is not listed or the table is absent.
atlas_taxon_guild <- function(name, guilds = atlas_guild_table()) {
  genus <- atlas_taxon_genus(name)
  found <- unname(guilds[genus])
  ifelse(is.na(genus) | is.na(found), ATLAS_GUILD_UNKNOWN, found)
}

#' One string standing for the guild table's contents.
#'
#' Part of every Maxent model's settings, so a changed table makes the stored
#' models stale and they refit (R/fit.R explains why this, rather than a guild
#' per model). Hashed from the genus-to-lifestyle pairs, not the file, so the
#' same table saved again does not count as a change.
atlas_guild_table_key <- function(guilds = atlas_guild_table()) {
  if (!length(guilds)) {
    return("none")
  }
  ordered <- guilds[order(names(guilds))]
  digest::digest(paste(names(ordered), ordered, sep = "=", collapse = ";"), algo = "sha256")
}
