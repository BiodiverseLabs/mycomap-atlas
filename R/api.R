# Helpers behind the HTTP routes. The logic lives here rather than in the
# plumber file so it can be tested without starting a server.

# The development API answers a browser on the developer's own machine. A
# wildcard would let any site that developer happens to visit read it, so an
# origin is matched exactly — never by prefix, which would accept
# http://localhost:5101.example.com.
ATLAS_DEFAULT_ORIGINS <- c("http://localhost:5101", "http://127.0.0.1:5101")

#' Origins the API will answer cross-site, from ATLAS_ALLOWED_ORIGINS.
atlas_allowed_origins <- function() {
  configured <- Sys.getenv("ATLAS_ALLOWED_ORIGINS", unset = "")
  if (!nzchar(configured)) {
    return(ATLAS_DEFAULT_ORIGINS)
  }
  origins <- trimws(strsplit(configured, ",", fixed = TRUE)[[1]])
  origins[nzchar(origins)]
}

#' The origin to echo back, or NULL when it is not allowed.
#'
#' "*" in the allowlist opens the API to every site. That is safe for the
#' public server because no answer here is sent with
#' Access-Control-Allow-Credentials, so a browser never lets another site's
#' page use a visitor's Atlas session: cross-site calls are anonymous unless
#' the calling page sends a token itself.
atlas_allowed_origin <- function(origin, allowed = atlas_allowed_origins()) {
  if (is.null(origin) || !length(origin)) {
    return(NULL)
  }
  origin <- as.character(origin)[[1]]
  if (!nzchar(origin)) {
    return(NULL)
  }
  if ("*" %in% allowed) {
    return("*")
  }
  if (!origin %in% allowed) {
    return(NULL)
  }
  origin
}

#' Response headers a page on another site may read.
atlas_exposed_headers <- function() {
  "X-RateLimit-Limit, X-RateLimit-Remaining, Retry-After, X-Atlas-Tier"
}

#' Where the OpenAPI description lives: the source tree when running from it,
#' the installed package otherwise.
atlas_openapi_path <- function(root = Sys.getenv("ATLAS_ROOT", unset = ".")) {
  source <- file.path(root, "inst", "api", "openapi.json")
  if (file.exists(source)) {
    return(source)
  }
  system.file("api", "openapi.json", package = "mycomapatlas")
}

#' Where the list of sources lives, found the same way as the OpenAPI file.
atlas_sources_path <- function(root = Sys.getenv("ATLAS_ROOT", unset = ".")) {
  source <- file.path(root, "inst", "api", "sources.json")
  if (file.exists(source)) {
    return(source)
  }
  system.file("api", "sources.json", package = "mycomapatlas")
}

#' The GET routes under /api/ a plumber file declares, with the parameters
#' each takes. The sign-in routes under /auth/ are pages a browser visits, not
#' API, and are left out.
#'
#' Read from the file's text, so the documentation test needs no server. A
#' route's parameters are its handler's arguments, less plumber's req and res;
#' a path like /api/taxa/<name> comes back in OpenAPI's form, /api/taxa/{name}.
atlas_plumber_routes <- function(path) {
  lines <- readLines(path, warn = FALSE)
  at <- grep("^#[*] @get ", lines)
  routes <- lapply(at, function(i) {
    route <- trimws(sub("^#[*] @get ", "", lines[[i]]))
    route <- gsub("<([a-z_]+)>", "{\\1}", route)
    rest <- lines[seq(i + 1L, length(lines))]
    header <- rest[grep("^function[(]", rest)[[1]]]
    inside <- sub("^function[(](.*)[)] *[{].*$", "\\1", header)
    args <- trimws(sub("=.*$", "", strsplit(inside, ",", fixed = TRUE)[[1]]))
    args <- setdiff(args[nzchar(args)], c("req", "res"))
    list(path = route, params = args)
  })
  names(routes) <- vapply(routes, `[[`, character(1), "path")
  routes[startsWith(names(routes), "/api/")]
}

#' Decode a taxon name taken from a URL path.
#'
#' Plumber leaves path parameters percent-encoded, and every species name has a
#' space in it. Decoding twice is harmless, since a decoded name has no percent
#' sign left.
atlas_decode_name <- function(name) {
  if (is.null(name) || !length(name)) {
    return("")
  }
  utils::URLdecode(as.character(name)[[1]])
}

#' One taxon's row, or NULL when the current pull does not hold it.
atlas_taxon_row <- function(taxa, name) {
  if (is.null(taxa) || !nrow(taxa)) {
    return(NULL)
  }
  row <- taxa[taxa$scientific_name == name, , drop = FALSE]
  if (!nrow(row)) {
    return(NULL)
  }
  as.list(row[1, ])
}

#' Where a taxon has been collected, aggregated to the public grid.
#'
#' Returns cell centres, never a record's own coordinates: this is the only
#' shape in which collection locations leave the machine.
atlas_public_cells <- function(records, name, degrees = ATLAS_PUBLIC_DEGREES) {
  empty <- data.frame(
    lat = numeric(), lng = numeric(), records = integer(),
    stringsAsFactors = FALSE
  )
  if (is.null(records) || !nrow(records)) {
    return(empty)
  }
  subset <- records[records$scientific_name == name, , drop = FALSE]
  if (!nrow(subset)) {
    return(empty)
  }
  keys <- atlas_locality_key(subset$latitude, subset$longitude, degrees = degrees)
  counts <- table(keys)
  parts <- do.call(rbind, strsplit(names(counts), ":", fixed = TRUE))
  data.frame(
    lat = (as.numeric(parts[, 1]) + 0.5) * degrees,
    lng = (as.numeric(parts[, 2]) + 0.5) * degrees,
    records = as.integer(counts),
    stringsAsFactors = FALSE
  )
}

#' The algorithm a request asks for, defaulting to Maxent. NULL when it names
#' something Atlas does not fit, so the route can answer 400 rather than guess.
atlas_request_algorithm <- function(value) {
  if (is.null(value) || !length(value) || !nzchar(as.character(value)[[1]])) {
    return("maxnet")
  }
  value <- as.character(value)[[1]]
  if (value %in% names(ATLAS_ALGORITHMS)) value else NULL
}

#' The newest results file of a study (benchmarks, sweeps), or NULL.
#'
#' Files are named <prefix>-<UTC stamp>.json, so the newest sorts last. A
#' study still running is served as it stands; it saves after every taxon.
atlas_latest_study <- function(kind, grid = "draft", prefix = NULL) {
  pattern <- paste0("^", prefix %||% "[a-z]+", "-[0-9T]+Z[.]json$")
  files <- sort(list.files(atlas_path(kind, grid), pattern = pattern, full.names = TRUE))
  if (!length(files)) {
    return(NULL)
  }
  tryCatch(
    jsonlite::fromJSON(files[[length(files)]], simplifyVector = FALSE),
    error = function(e) NULL
  )
}

#' Plain labels for the models, for the web app.
atlas_algorithm_labels <- function() {
  lapply(ATLAS_ALGORITHMS, function(a) a$label)
}

#' What the status route reports: the pull's own manifest where this machine
#' made the pull, and otherwise the summary a release carried.
atlas_status_manifest <- function() {
  manifest <- atlas_read_manifest()
  if (!is.null(manifest)) return(manifest)
  path <- atlas_public_pull_path()
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

#' The published cells for every taxon, or NULL when this machine has none.
atlas_read_public_cells <- function() {
  path <- atlas_public_cells_path()
  if (!file.exists(path)) return(NULL)
  cells <- utils::read.delim(gzfile(path), sep = "\t", quote = "", comment.char = "",
                             colClasses = c("character", "numeric", "numeric", "integer"),
                             check.names = FALSE, stringsAsFactors = FALSE)
  cells
}

#' One taxon's collection cells: aggregated from the pull when this machine
#' has it, or read from what a release published.
atlas_taxon_cells <- function(name, occurrences = NULL, public = NULL) {
  if (!is.null(occurrences)) {
    return(atlas_public_cells(occurrences, name))
  }
  if (is.null(public) || !nrow(public)) {
    return(atlas_public_cells(NULL, name))
  }
  rows <- public[public$taxon == name, c("lat", "lng", "records"), drop = FALSE]
  rownames(rows) <- NULL
  rows
}
