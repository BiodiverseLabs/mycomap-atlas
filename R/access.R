# Who may read the API, and how often.
#
# Reads are open. Tokens identify a caller; they do not protect the server.
# What protects it is a rate limit on every caller: anonymous callers get a
# modest allowance per address, and a token raises it. A flood still reaches
# the server before any key could be checked, so requiring tokens would not
# stop one, and it would force the site's own pages, which call this API from
# visitors' browsers, through an exemption that anyone can claim.
# ATLAS_REQUIRE_TOKEN turns every route token-only for a deployment that wants
# it anyway.
#
# Tokens are issued by mycomap.org, per account, and approved there by an
# admin (https://mycomap.org/atlas-tokens). A script sends one as
# "Authorization: Bearer <token>". Atlas never sees the account: it asks .org's
# introspection route whether a token is live and gets back only its status,
# id and tier. The shared secret for that route comes from the environment, so
# this code stays open while the secret does not. A copy of Atlas without it
# reads tokens as absent and serves everyone at the anonymous rate.
#
# A person signed in through mycomap.org (R/auth.R) counts like a standard
# token, per person. A live token or a session also unlocks downloads.

# Requests per minute. Measured on the site (2026-09-29): the home page makes
# 6 API requests, a taxon page 9 (three models and their maps), and typing a
# name into the taxa search up to one per letter. 300 lets a quick reader open
# a taxon page every couple of seconds for a minute, several people behind
# one address included, and still stops a script well short of the signed-in
# allowance.
ATLAS_RATE_DEFAULTS <- c(anonymous = 300, standard = 1200, bulk = 6000)

# How long an introspection answer is trusted, in seconds. A revoked token
# stops working within this long; a rejected one is re-asked sooner, so a
# token approved a moment ago starts working quickly. When .org cannot be
# asked nothing is cached: the caller is treated as anonymous for that request
# and .org is asked again on the next.
ATLAS_KEY_TTL_ACTIVE <- 300
ATLAS_KEY_TTL_INACTIVE <- 60

# The longest token worth asking .org about; real ones are 49 characters.
ATLAS_KEY_MAX_LENGTH <- 512

# .org's introspection route, below ATLAS_SIGNIN_ISSUER.
ATLAS_INTROSPECT_PATH <- "/api/service-keys/introspect"

#' Access settings from the environment.
#'
#' Tokens are checked only when ATLAS_INTROSPECTION_SECRET is set. The route
#' is ATLAS_SIGNIN_ISSUER's (https://mycomap.org by default) unless
#' ATLAS_KEY_INTROSPECT_URL names another, such as a stand-in for testing.
atlas_access_config <- function() {
  number <- function(name, default) {
    value <- suppressWarnings(as.numeric(Sys.getenv(name, unset = "")))
    if (is.na(value) || value <= 0) default else value
  }
  flag <- function(name) tolower(Sys.getenv(name, unset = "")) %in% c("1", "true", "yes")
  secret <- Sys.getenv("ATLAS_INTROSPECTION_SECRET", unset = "")
  url <- Sys.getenv("ATLAS_KEY_INTROSPECT_URL", unset = "")
  if (!nzchar(url)) {
    issuer_text <- Sys.getenv("ATLAS_SIGNIN_ISSUER", unset = "")
    issuer <- atlas_origin_of(if (nzchar(issuer_text)) issuer_text else "https://mycomap.org")
    url <- if (is.null(issuer)) "" else paste0(issuer, ATLAS_INTROSPECT_PATH)
  }
  list(
    rates = c(
      anonymous = number("ATLAS_RATE_ANONYMOUS", ATLAS_RATE_DEFAULTS[["anonymous"]]),
      standard = number("ATLAS_RATE_STANDARD", ATLAS_RATE_DEFAULTS[["standard"]]),
      bulk = number("ATLAS_RATE_BULK", ATLAS_RATE_DEFAULTS[["bulk"]])
    ),
    require_token = flag("ATLAS_REQUIRE_TOKEN"),
    # Only both together can check a token.
    introspect_url = if (nzchar(url) && nzchar(secret)) url else "",
    introspect_secret = secret
  )
}

#' [CONFIG-ALERT] lines for access settings, printed when the API starts.
atlas_access_alerts <- function(config) {
  if (nzchar(config$introspect_url)) {
    return(character())
  }
  "[CONFIG-ALERT] ATLAS_INTROSPECTION_SECRET is not set: API tokens are ignored and cannot unlock downloads."
}

#' Mutable state the access filter keeps between requests.
atlas_access_state <- function() {
  state <- new.env(parent = emptyenv())
  state$buckets <- new.env(parent = emptyenv())
  state$keys <- new.env(parent = emptyenv())
  state
}

#' Take one request from a caller's bucket.
#'
#' A token bucket holding a minute's allowance that refills continuously, so a
#' burst up to the allowance is fine and a sustained rate above it is not.
atlas_rate_take <- function(state, id, per_minute, now = as.numeric(Sys.time())) {
  bucket <- state$buckets[[id]]
  if (is.null(bucket)) {
    bucket <- list(tokens = per_minute, at = now)
  }
  refill <- (now - bucket$at) * per_minute / 60
  tokens <- min(per_minute, bucket$tokens + max(0, refill))
  allowed <- tokens >= 1
  if (allowed) tokens <- tokens - 1
  assign(id, list(tokens = tokens, at = now), envir = state$buckets)
  list(
    allowed = allowed,
    limit = per_minute,
    remaining = floor(tokens),
    retry_after = if (allowed) 0 else ceiling((1 - tokens) * 60 / per_minute)
  )
}

#' Forget buckets nobody has touched for ten minutes, so the table of
#' addresses cannot grow without bound. A full bucket and a forgotten one
#' behave the same.
atlas_rate_sweep <- function(state, now = as.numeric(Sys.time()), idle = 600) {
  for (id in ls(state$buckets, all.names = TRUE)) {
    if (now - state$buckets[[id]]$at > idle) rm(list = id, envir = state$buckets)
  }
  invisible(state)
}

#' Whether an address is this machine.
atlas_is_loopback <- function(address) {
  address <- tolower(address %||% "")
  grepl("^127[.]", address) || address %in% c("::1", "::ffff:127.0.0.1", "0:0:0:0:0:0:0:1")
}

#' The address a request came from.
#'
#' Behind nginx on the same machine every request arrives from 127.0.0.1, and
#' nginx appends the address that connected to it to X-Forwarded-For. So that
#' header is believed only when the request came from this machine, and only
#' its right-most entry, the one nginx wrote: anything to the left of it is
#' whatever the caller sent, and would let anyone pick their own bucket. A
#' request straight from another machine is counted by its own address. (Behind
#' Cloudflare, nginx's real_ip module has to restore the visitor's address
#' first, or every visitor arriving through one Cloudflare edge would share an
#' allowance.)
atlas_client_ip <- function(req) {
  peer <- req$REMOTE_ADDR
  peer <- if (length(peer) && !is.na(peer[[1]]) && nzchar(peer[[1]])) peer[[1]] else "unknown"
  if (!atlas_is_loopback(peer)) {
    return(peer)
  }
  forwarded <- req$HTTP_X_FORWARDED_FOR
  if (!length(forwarded) || is.na(forwarded[[1]]) || !nzchar(forwarded[[1]])) {
    return(peer)
  }
  entries <- trimws(strsplit(forwarded[[1]], ",", fixed = TRUE)[[1]])
  entries <- entries[nzchar(entries)]
  if (!length(entries)) peer else entries[[length(entries)]]
}

#' The token a request carries in "Authorization: Bearer <token>", or "".
atlas_request_token <- function(req) {
  header <- req$HTTP_AUTHORIZATION
  if (!length(header) || is.na(header[[1]])) {
    return("")
  }
  match <- regmatches(header[[1]], regexec("^[Bb][Ee][Aa][Rr][Ee][Rr] +([^ ]+) *$", header[[1]]))[[1]]
  if (length(match) == 2L) match[[2]] else ""
}

#' Ask mycomap.org whether a token is live. Returns the parsed answer, or
#' NULL when .org could not be asked.
atlas_introspect_http <- function(key, url, secret, timeout = 5) {
  handle <- curl::new_handle()
  curl::handle_setheaders(
    handle,
    "Authorization" = paste("Bearer", secret),
    "Content-Type" = "application/json"
  )
  curl::handle_setopt(
    handle,
    postfields = as.character(jsonlite::toJSON(list(key = key), auto_unbox = TRUE)),
    timeout = timeout
  )
  response <- tryCatch(curl::curl_fetch_memory(url, handle = handle), error = function(e) NULL)
  if (is.null(response) || response$status_code != 200L) {
    return(NULL)
  }
  tryCatch(
    jsonlite::fromJSON(rawToChar(response$content), simplifyVector = TRUE),
    error = function(e) NULL
  )
}

atlas_key_id <- function(key) digest::digest(key, algo = "sha256", serialize = FALSE)

#' Whether a token's answer is already known, so checking it costs nothing.
atlas_key_cached <- function(key, state, now = as.numeric(Sys.time())) {
  cached <- state$keys[[atlas_key_id(key)]]
  !is.null(cached) && cached$expires > now
}

#' What a token is: its tier when live, or why not.
#'
#' Answers are cached by a hash of the token, never the token itself. When
#' .org cannot be asked the answer is "unavailable" and is not cached.
#' transport is the call to .org, replaced in tests.
atlas_check_key <- function(key, state, config, now = as.numeric(Sys.time()),
                            transport = atlas_introspect_http) {
  if (!nzchar(config$introspect_url)) {
    return(list(active = FALSE, reason = "not_checked"))
  }
  if (nchar(key) > ATLAS_KEY_MAX_LENGTH) {
    return(list(active = FALSE, reason = "unknown"))
  }
  id <- atlas_key_id(key)
  cached <- state$keys[[id]]
  if (!is.null(cached) && cached$expires > now) {
    return(cached$answer)
  }
  reply <- tryCatch(transport(key, config$introspect_url, config$introspect_secret),
                    error = function(e) NULL)
  if (!is.list(reply) || !is.logical(reply$active) || length(reply$active) != 1L ||
      is.na(reply$active)) {
    return(list(active = FALSE, reason = "unavailable"))
  }
  answer <- if (isTRUE(reply$active) && identical(reply$service, "atlas")) {
    tier <- as.character(reply$tier %||% "standard")
    list(active = TRUE, tier = tier, key_id = as.character(reply$keyId %||% ""))
  } else if (isTRUE(reply$active)) {
    list(active = FALSE, reason = "wrong_service")
  } else {
    list(active = FALSE, reason = as.character(reply$reason %||% "unknown"))
  }
  ttl <- if (isTRUE(answer$active)) ATLAS_KEY_TTL_ACTIVE else ATLAS_KEY_TTL_INACTIVE
  assign(id, list(answer = answer, expires = now + ttl), envir = state$keys)
  answer
}

#' Decide one request: let it through, refuse the token, or slow it down.
#'
#' Returns status (NULL to proceed), the headers to send, a body for a
#' refusal, and the caller's identity for the routes: via "token", "session"
#' or "anonymous", with the tier its allowance comes from.
#'
#' A token .org rejects is refused outright rather than served at the
#' anonymous rate, so a caller learns their token is wrong instead of quietly
#' getting less. When .org cannot be asked, or tokens cannot be checked on
#' this copy, the caller is anonymous: served at the anonymous rate, and not
#' allowed to download. A token not yet known costs its address one anonymous
#' request before .org is asked, so a stream of made-up tokens cannot make
#' Atlas call .org faster than the anonymous rate.
atlas_access_decision <- function(req, state, config, now = as.numeric(Sys.time()),
                                  transport = atlas_introspect_http, signin = NULL) {
  key <- atlas_request_token(req)
  identity <- list(via = "anonymous", tier = "anonymous")
  ip_bucket <- paste0("ip:", atlas_client_ip(req))
  bucket <- ip_bucket

  slow_down <- function(taken, tier) {
    list(
      status = 429L,
      headers = list(
        `X-RateLimit-Limit` = as.character(taken$limit),
        `X-RateLimit-Remaining` = as.character(taken$remaining),
        `X-Atlas-Tier` = tier,
        `Retry-After` = as.character(taken$retry_after),
        `Cache-Control` = "no-store"
      ),
      body = list(
        error = "Too many requests. Slow down, or sign in or use a token for a higher limit.",
        retry_after = taken$retry_after
      ),
      identity = identity
    )
  }

  if (nzchar(key)) {
    if (nzchar(config$introspect_url) && !atlas_key_cached(key, state, now)) {
      taken <- atlas_rate_take(state, ip_bucket, config$rates[["anonymous"]], now)
      if (!taken$allowed) return(slow_down(taken, "anonymous"))
    }
    checked <- atlas_check_key(key, state, config, now, transport)
    if (isTRUE(checked$active)) {
      tier <- if (checked$tier %in% names(config$rates)) checked$tier else "standard"
      identity <- list(via = "token", tier = tier)
      bucket <- paste0("key:", checked$key_id)
    } else if (!checked$reason %in% c("unavailable", "not_checked")) {
      return(list(
        status = 401L,
        headers = list(`Cache-Control` = "no-store", `WWW-Authenticate` = "Bearer"),
        body = list(error = "This token is not valid.", reason = checked$reason),
        identity = identity
      ))
    }
  }

  if (identical(identity$via, "anonymous") && !is.null(signin)) {
    session <- atlas_request_session(req, signin, now)
    if (!is.null(session)) {
      identity <- list(via = "session", tier = "standard", name = session$name)
      bucket <- paste0("user:", session$sub)
    }
  }

  if (config$require_token && identical(identity$via, "anonymous")) {
    return(list(
      status = 401L,
      headers = list(`Cache-Control` = "no-store", `WWW-Authenticate` = "Bearer"),
      body = list(error = "This server needs a token. Send it as an Authorization: Bearer header."),
      identity = identity
    ))
  }

  taken <- atlas_rate_take(state, bucket, config$rates[[identity$tier]], now)
  if (!taken$allowed) {
    return(slow_down(taken, identity$tier))
  }
  headers <- list(
    `X-RateLimit-Limit` = as.character(taken$limit),
    `X-RateLimit-Remaining` = as.character(taken$remaining),
    `X-Atlas-Tier` = identity$tier
  )
  list(status = NULL, headers = headers, body = NULL, identity = identity)
}

#' How long a shared cache may keep a response.
#'
#' Everything here changes only when a new release lands, so a CDN in front of
#' the API can answer repeat requests without reaching it. A map requested with
#' its version (?v=) never changes at that address. Rate-limit headers go out
#' with a cached copy too, which only ever over-reports what is left.
atlas_cache_control <- function(path, query = "") {
  # (An error answer is never kept, whatever its path: see
  # atlas_settle_cache_control, which runs after the route has answered.)
  if (!startsWith(path, "/api/")) {
    return(NULL)
  }
  # Who is asking decides these answers, so no shared cache may keep them: a
  # CDN that kept a download's redirect would hand it to anyone.
  if (identical(path, "/api/me") || endsWith(path, "/raster.tif")) {
    return("private, no-store")
  }
  # A Here answer is about the point a visitor chose, which sits in the query
  # to about 10 m. Kept, it would sit in nginx's cache (the cache key) for up
  # to an hour; and points differ from visitor to visitor, so a cache would
  # store them without ever serving one twice.
  if (identical(path, "/api/here")) {
    return("private, no-store")
  }
  if ((endsWith(path, "/map.png") || endsWith(path, "/ensemble.png")) &&
      grepl("(^|&)v=", sub("^[?]", "", query))) {
    return("public, max-age=31536000, immutable")
  }
  if (identical(path, "/api/status")) {
    return("public, max-age=60")
  }
  "public, max-age=300"
}

#' The Cache-Control an answer leaves with, once its status is known.
#'
#' atlas_cache_control sets it from the path before the route runs, and a
#' route can still answer 404 or 503, or fail with a 500. A kept error is worse
#' than a slow answer: nginx or Cloudflare would hand a passing outage to every
#' visitor for five minutes. So any answer from 400 up leaves with no-store.
atlas_settle_cache_control <- function(status, current = NULL) {
  if (is.numeric(status) && length(status) == 1L && status >= 400) return("no-store")
  current
}

# ---- what a request may ask for ------------------------------------------------

# Query parameters that must be numbers wherever a route takes them. Each
# route still sets its own range; this only refuses what is not a number at
# all, which used to reach as.numeric() and come back as a 500 or a garbage
# page.
ATLAS_NUMBER_PARAMS <- c("limit", "offset", "min_localities", "lat", "lng", "min_score",
                         "nearby_km", "width")

# The most rows /api/taxa returns in one page.
ATLAS_TAXA_LIMIT_MAX <- 1000L

#' The grid a request names, or NULL when it is not one Atlas has. The grid
#' becomes part of a file path, so anything else ("../x") is refused before
#' a route sees it.
atlas_request_grid <- function(grid) {
  if (is.character(grid) && length(grid) == 1L && grid %in% names(ATLAS_GRID_RESOLUTIONS)) {
    grid
  } else {
    NULL
  }
}

#' A query parameter as one finite number, or NULL when it is not one.
atlas_request_number <- function(x) {
  if (is.null(x) || length(x) != 1L) return(NULL)
  value <- suppressWarnings(as.numeric(trimws(as.character(x))))
  if (is.finite(value)) value else NULL
}

#' The query string as a named list of values, as a browser sent it.
atlas_query_args <- function(query = "") {
  query <- sub("^[?]", "", query %||% "")
  if (!nzchar(query)) return(list())
  pairs <- strsplit(strsplit(query, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
  pairs <- pairs[vapply(pairs, function(p) length(p) >= 1L && nzchar(p[[1]]), logical(1))]
  decode <- function(x) utils::URLdecode(gsub("+", " ", x, fixed = TRUE))
  keys <- vapply(pairs, function(p) decode(p[[1]]), character(1))
  values <- lapply(pairs, function(p) if (length(p) > 1L) decode(paste(p[-1], collapse = "=")) else "")
  out <- list()
  for (i in seq_along(keys)) out[[keys[[i]]]] <- c(out[[keys[[i]]]], values[[i]])
  out
}

#' What is wrong with a request's query, in words for the caller, or NULL
#' when nothing is. Every /api/ route goes through it (the inputs filter in
#' inst/plumber/atlas.R), so a route added later cannot forget it.
atlas_query_problem <- function(query = "") {
  args <- atlas_query_args(query)
  if (!is.null(args$grid) && is.null(atlas_request_grid(args$grid))) {
    return(paste0("grid must be one of: ", paste(names(ATLAS_GRID_RESOLUTIONS), collapse = ", ")))
  }
  for (name in intersect(ATLAS_NUMBER_PARAMS, names(args))) {
    if (is.null(atlas_request_number(args[[name]]))) {
      return(paste0(name, " must be a number"))
    }
  }
  NULL
}

#' An error answered as JSON, whatever the route would have sent on success.
#' Image routes used to answer their errors with an empty body. Returned as
#' res it skips the serializer, and with it the hook that marks errors
#' no-store, so it says no-store itself: replacing the access filter's
#' header, not adding a second one beside it.
atlas_json_error <- function(res, status, message) {
  res$status <- as.integer(status)
  res$headers[["Cache-Control"]] <- "no-store"
  res$setHeader("Content-Type", "application/json")
  res$body <- as.character(jsonlite::toJSON(list(error = message), auto_unbox = TRUE))
  res
}
