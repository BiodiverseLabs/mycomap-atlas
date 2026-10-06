# States, provinces and territories: where each taxon has been recorded, as a
# list people can open in a spreadsheet.
#
# The pull's state field is free text from .org. US and Canadian records are
# mostly clean full names; Mexican ones mix names, Spanish and English forms
# and abbreviations (VER, Ver., Veracruz de Ignacio de la Llave), and Puerto
# Rican ones often carry the municipality. Each record is matched to one
# canonical region here, so a checklist never splits Quebec from Québec.
#
# A region is coarser than any published grid, so this table may be published
# as it stands: it holds no coordinate.

# Each region: country code, its ISO 3166-2 code, its name, and other spellings
# seen in the data or in common use. Puerto Rico and the US Virgin Islands are
# listed under the United States, as ISO 3166-2:US lists them.
atlas_region_list <- function() {
  region <- function(country, code, name, ...) {
    list(country = country, code = code, name = name, aliases = c(...))
  }
  list(
    region("US", "US-AL", "Alabama"),
    region("US", "US-AK", "Alaska"),
    region("US", "US-AZ", "Arizona"),
    region("US", "US-AR", "Arkansas"),
    region("US", "US-CA", "California"),
    region("US", "US-CO", "Colorado"),
    region("US", "US-CT", "Connecticut"),
    region("US", "US-DE", "Delaware"),
    region("US", "US-FL", "Florida"),
    region("US", "US-GA", "Georgia"),
    region("US", "US-HI", "Hawaii"),
    region("US", "US-ID", "Idaho"),
    region("US", "US-IL", "Illinois"),
    region("US", "US-IN", "Indiana"),
    region("US", "US-IA", "Iowa"),
    region("US", "US-KS", "Kansas"),
    region("US", "US-KY", "Kentucky"),
    region("US", "US-LA", "Louisiana"),
    region("US", "US-ME", "Maine"),
    region("US", "US-MD", "Maryland"),
    region("US", "US-MA", "Massachusetts"),
    region("US", "US-MI", "Michigan"),
    region("US", "US-MN", "Minnesota"),
    region("US", "US-MS", "Mississippi"),
    region("US", "US-MO", "Missouri"),
    region("US", "US-MT", "Montana"),
    region("US", "US-NE", "Nebraska"),
    region("US", "US-NV", "Nevada"),
    region("US", "US-NH", "New Hampshire"),
    region("US", "US-NJ", "New Jersey"),
    region("US", "US-NM", "New Mexico"),
    region("US", "US-NY", "New York"),
    region("US", "US-NC", "North Carolina"),
    region("US", "US-ND", "North Dakota"),
    region("US", "US-OH", "Ohio"),
    region("US", "US-OK", "Oklahoma"),
    region("US", "US-OR", "Oregon"),
    region("US", "US-PA", "Pennsylvania"),
    region("US", "US-RI", "Rhode Island"),
    region("US", "US-SC", "South Carolina"),
    region("US", "US-SD", "South Dakota"),
    region("US", "US-TN", "Tennessee"),
    region("US", "US-TX", "Texas"),
    region("US", "US-UT", "Utah"),
    region("US", "US-VT", "Vermont"),
    region("US", "US-VA", "Virginia"),
    region("US", "US-WA", "Washington"),
    region("US", "US-WV", "West Virginia"),
    region("US", "US-WI", "Wisconsin"),
    region("US", "US-WY", "Wyoming"),
    region("US", "US-DC", "District of Columbia", "Washington DC", "Washington D.C."),
    region("US", "US-PR", "Puerto Rico"),
    region("US", "US-VI", "U.S. Virgin Islands", "US Virgin Islands", "Virgin Islands",
           "Saint Croix", "Saint John", "Saint Thomas", "St. Croix", "St. John", "St. Thomas"),

    region("CA", "CA-AB", "Alberta"),
    region("CA", "CA-BC", "British Columbia"),
    region("CA", "CA-MB", "Manitoba"),
    region("CA", "CA-NB", "New Brunswick"),
    region("CA", "CA-NL", "Newfoundland and Labrador", "Newfoundland"),
    region("CA", "CA-NS", "Nova Scotia"),
    region("CA", "CA-NT", "Northwest Territories"),
    region("CA", "CA-NU", "Nunavut"),
    region("CA", "CA-ON", "Ontario"),
    region("CA", "CA-PE", "Prince Edward Island"),
    region("CA", "CA-QC", "Quebec"),
    region("CA", "CA-SK", "Saskatchewan"),
    region("CA", "CA-YT", "Yukon", "Yukon Territory"),

    region("MX", "MX-AGU", "Aguascalientes", "AGS"),
    region("MX", "MX-BCN", "Baja California", "BC"),
    region("MX", "MX-BCS", "Baja California Sur"),
    region("MX", "MX-CAM", "Campeche"),
    region("MX", "MX-CHP", "Chiapas", "CHIS"),
    region("MX", "MX-CHH", "Chihuahua", "CHIH"),
    region("MX", "MX-CMX", "Mexico City", "Ciudad de Mexico", "CDMX", "Distrito Federal", "DF"),
    region("MX", "MX-COA", "Coahuila", "Coahuila de Zaragoza", "COAH"),
    region("MX", "MX-COL", "Colima"),
    region("MX", "MX-DUR", "Durango", "DGO"),
    region("MX", "MX-GUA", "Guanajuato", "GTO"),
    region("MX", "MX-GRO", "Guerrero"),
    region("MX", "MX-HID", "Hidalgo"),
    region("MX", "MX-JAL", "Jalisco"),
      # "Mexico" filed as a Mexican state means the state, not the country.
    region("MX", "MX-MEX", "State of Mexico", "Estado de Mexico", "Mexico", "EDOMEX"),
    region("MX", "MX-MIC", "Michoacán", "Michoacan de Ocampo", "MICH"),
    region("MX", "MX-MOR", "Morelos"),
    region("MX", "MX-NAY", "Nayarit"),
    region("MX", "MX-NLE", "Nuevo León", "NL"),
    region("MX", "MX-OAX", "Oaxaca"),
    region("MX", "MX-PUE", "Puebla"),
    region("MX", "MX-QUE", "Querétaro", "Queretaro de Arteaga", "QRO"),
    region("MX", "MX-ROO", "Quintana Roo", "QROO"),
    region("MX", "MX-SLP", "San Luis Potosí"),
    region("MX", "MX-SIN", "Sinaloa"),
    region("MX", "MX-SON", "Sonora"),
    region("MX", "MX-TAB", "Tabasco"),
    region("MX", "MX-TAM", "Tamaulipas", "TAMPS"),
    region("MX", "MX-TLA", "Tlaxcala"),
    region("MX", "MX-VER", "Veracruz", "Veracruz de Ignacio de la Llave", "Ver"),
    region("MX", "MX-YUC", "Yucatán"),
    region("MX", "MX-ZAC", "Zacatecas")
  )
}

ATLAS_COUNTRY_NAMES <- c(US = "United States", CA = "Canada", MX = "Mexico")

#' A spelling reduced to what tells two regions apart: no case, accents or
#' punctuation. "Québec", "quebec" and "Quebec." all become "quebec".
atlas_region_key <- function(text) {
  text <- enc2utf8(as.character(text))
  text[is.na(text)] <- ""
  text <- chartr("áéíóúüñÁÉÍÓÚÜÑ",
                 "aeiouunAEIOUUN", text)
  text <- tolower(gsub("[^A-Za-z0-9]+", " ", text))
  trimws(gsub(" +", " ", text))
}

#' Every spelling's key, pointing at its region: names, aliases and codes,
#' with and without the country prefix. Built once per session.
atlas_region_lookup <- local({
  built <- NULL
  function() {
    if (!is.null(built)) return(built)
    regions <- atlas_region_list()
    rows <- do.call(rbind, lapply(regions, function(r) {
      spellings <- c(r$name, r$aliases, r$code, sub("^[A-Z]+-", "", r$code))
      data.frame(key = atlas_region_key(spellings), country = r$country, code = r$code,
                 region = r$name, stringsAsFactors = FALSE)
    }))
    built <<- unique(rows)
    built
  }
})

#' The canonical region of each record, from its country and state fields.
#'
#' A recognised state name decides the region and its country, whatever the
#' country field says: "New York" filed under Canada is New York. Otherwise a
#' Puerto Rican or Virgin Islands record lands in its territory (the state
#' field there is often a municipality), and anything else keeps its own text,
#' or "Not recorded" when it has none, under its country.
#'
#' Returns one row per input: country (name), country_code, region, code.
atlas_region_of <- function(country, state) {
  country <- toupper(trimws(as.character(country)))
  country[is.na(country)] <- ""
  state <- trimws(as.character(state))
  state[is.na(state)] <- ""
  pairs <- unique(data.frame(country = country, state = state, stringsAsFactors = FALSE))
  lookup <- atlas_region_lookup()

  resolved <- lapply(seq_len(nrow(pairs)), function(i) {
    key <- atlas_region_key(pairs$state[[i]])
    hits <- lookup[lookup$key == key & nzchar(key), , drop = FALSE]
    # Two-letter codes can mean different places in different countries
    # (BC, NL): the record's own country settles it.
    if (nrow(hits) > 1) {
      own <- hits[hits$country == pairs$country[[i]], , drop = FALSE]
      hits <- if (nrow(own)) own else hits[0, , drop = FALSE]
    }
    if (nrow(hits) == 1) {
      return(c(hits$country, hits$region, hits$code))
    }
    if (pairs$country[[i]] %in% c("PR", "PU")) return(c("US", "Puerto Rico", "US-PR"))
    if (pairs$country[[i]] == "VI") return(c("US", "U.S. Virgin Islands", "US-VI"))
    c(pairs$country[[i]], if (nzchar(pairs$state[[i]])) pairs$state[[i]] else "Not recorded", "")
  })
  resolved <- do.call(rbind, resolved)
  at <- match(paste(country, state, sep = "\t"), paste(pairs$country, pairs$state, sep = "\t"))
  code <- resolved[at, 1]
  data.frame(
    country = ifelse(code %in% names(ATLAS_COUNTRY_NAMES), ATLAS_COUNTRY_NAMES[code], code),
    country_code = code,
    region = resolved[at, 2],
    code = resolved[at, 3],
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Every taxon in every region it has been recorded in, with its records and
#' independent localities there. Sorted by country, region, then name.
atlas_region_table <- function(occurrences) {
  empty <- data.frame(
    taxon = character(), country = character(), country_code = character(),
    region = character(), code = character(), records = integer(), localities = integer(),
    stringsAsFactors = FALSE
  )
  if (is.null(occurrences) || !nrow(occurrences)) return(empty)
  where <- atlas_region_of(occurrences$country, occurrences$state)
  group <- paste(occurrences$scientific_name, where$country_code, where$region, sep = "\t")
  first <- !duplicated(group)
  out <- data.frame(taxon = occurrences$scientific_name[first], where[first, , drop = FALSE],
                    stringsAsFactors = FALSE)
  # Counted by position, not with table(): a factor of 47k groups is slow.
  at <- match(group, group[first])
  key <- atlas_locality_key(occurrences$latitude, occurrences$longitude)
  new_place <- !duplicated(paste(at, key))
  out$records <- tabulate(at, nbins = sum(first))
  out$localities <- tabulate(at[new_place], nbins = sum(first))
  out <- out[order(out$country, out$region, out$taxon), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The regions file a release carries, read by the API where the pull is not.
atlas_public_regions_path <- function() {
  atlas_path("public", "regions.tsv.gz")
}

#' The published region table, or NULL when this machine has none.
atlas_read_public_regions <- function() {
  path <- atlas_public_regions_path()
  if (!file.exists(path)) return(NULL)
  utils::read.delim(gzfile(path, encoding = "UTF-8"), sep = "\t", quote = "", comment.char = "",
                    colClasses = c(rep("character", 5), "integer", "integer"),
                    na.strings = character(0), check.names = FALSE, stringsAsFactors = FALSE,
                    encoding = "UTF-8")
}

#' One row per region: how many taxa and records it holds.
atlas_regions_summary <- function(table) {
  if (is.null(table) || !nrow(table)) {
    return(data.frame(country = character(), region = character(), code = character(),
                      taxa = integer(), records = integer(), stringsAsFactors = FALSE))
  }
  group <- paste(table$country_code, table$region, sep = "\t")
  first <- !duplicated(group)
  out <- table[first, c("country", "region", "code"), drop = FALSE]
  out$taxa <- as.integer(tabulate(match(group, group[first])))
  out$records <- as.integer(vapply(split(table$records, factor(group, levels = group[first])),
                                   sum, numeric(1)))
  rownames(out) <- NULL
  out
}

#' The rows of a checklist: everything, or one region, one country, or one
#' taxon. A region is asked for by its code (US-IN) or its name (Indiana); a
#' country by its code (US). NULL when the region names nothing in the table,
#' so the route can say so rather than hand back an empty file.
atlas_checklist <- function(table, region = "", taxon = "") {
  rows <- table
  region <- trimws(region %||% "")
  taxon <- trimws(taxon %||% "")
  if (nzchar(region)) {
    wanted <- toupper(region)
    keep <- toupper(rows$code) == wanted | rows$country_code == wanted |
      atlas_region_key(rows$region) == atlas_region_key(region)
    if (!any(keep)) return(NULL)
    rows <- rows[keep, , drop = FALSE]
  }
  if (nzchar(taxon)) {
    rows <- rows[rows$taxon == taxon, , drop = FALSE]
  }
  rownames(rows) <- NULL
  rows
}

#' A checklist as CSV text that Excel opens with its accents intact: UTF-8
#' with a byte-order mark, every field quoted, a link to each taxon's page.
atlas_checklist_csv <- function(rows, origin = atlas_site_origin()) {
  out <- data.frame(
    country = rows$country,
    state_province = rows$region,
    region_code = rows$code,
    scientific_name = rows$taxon,
    validated_records = rows$records,
    independent_localities = rows$localities,
    atlas_page = paste0(origin, "/taxa/", vapply(rows$taxon, utils::URLencode, "", reserved = TRUE),
                        recycle0 = TRUE),
    stringsAsFactors = FALSE
  )
  quote <- function(x) paste0("\"", gsub("\"", "\"\"", x, fixed = TRUE), "\"")
  lines <- c(
    paste(quote(names(out)), collapse = ","),
    if (nrow(out)) do.call(paste, c(lapply(out, function(col) {
      if (is.numeric(col)) as.character(col) else quote(col)
    }), sep = ","))
  )
  paste0("\ufeff", paste(lines, collapse = "\r\n"), "\r\n")
}

#' A file name for a checklist download that says what is in it.
atlas_checklist_filename <- function(region = "", taxon = "") {
  parts <- c("mycomap-atlas-checklist", trimws(region %||% ""), trimws(taxon %||% ""))
  parts <- parts[nzchar(parts)]
  name <- tolower(gsub("[^A-Za-z0-9]+", "-", paste(parts, collapse = "-")))
  paste0(gsub("^-|-$", "", name), ".csv")
}

#' The public site's origin, for links written into downloaded files.
atlas_site_origin <- function() {
  origin <- sub("/+$", "", Sys.getenv("ATLAS_PUBLIC_ORIGIN", unset = ""))
  if (nzchar(origin)) origin else "https://atlas.mycomap.org"
}
