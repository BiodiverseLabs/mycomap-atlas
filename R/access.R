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
# admin. Atlas never sees the account: it asks .org's introspection route
# whether a token is live and gets back only its status, id and tier. The
# route and a shared secret come from the environment, so this code stays
# open while the secret does not. A copy of Atlas without them reads tokens as
# absent and serves everyone at the anonymous rate.

# Requests per minute. A page of the site makes about ten requests.
ATLAS_RATE_DEFAULTS <- c(anonymous = 120, standard = 1200, bulk = 6000)

# How long an introspection answer is trusted, in seconds. A revoked token
# stops working within this long; a rejected one is re-asked sooner, so a
# token approved a moment ago starts working quickly.
ATLAS_KEY_TTL_ACTIVE <- 300
ATLAS_KEY_TTL_INACTIVE <- 60
ATLAS_KEY_TTL_UNAVAILABLE <- 30

#' Access settings from the environment.
atlas_access_config <- function() {
  number <- function(name, default) {
    value <- suppressWarnings(as.numeric(Sys.getenv(name, unset = "")))
    if (is.na(value) || value <= 0) default else value
  }
  flag <- function(name) tolower(Sys.getenv(name, unset = "")) %in% c("1", "true", "yes")
  url <- Sys.getenv("ATLAS_KEY_INTROSPECT_URL", unset = "")
  secret <- Sys.getenv("ATLAS_KEY_INTROSPECT_SECRET", unset = "")
  list(
    rates = c(
      anonymous = number("ATLAS_RATE_ANONYMOUS", ATLAS_RATE_DEFAULTS[["anonymous"]]),
      standard = number("ATLAS_RATE_STANDARD", ATLAS_RATE_DEFAULTS[["standard"]]),
      bulk = number("ATLAS_RATE_BULK", ATLAS_RATE_DEFAULTS[["bulk"]])
    ),
    require_token = flag("ATLAS_REQUIRE_TOKEN"),
    # Only both together can check a token.
    introspect_url = if (nzchar(url) && nzchar(secret)) url else "",
    introspect_secret = secret,
    client_ip_header = Sys.getenv("ATLAS_CLIENT_IP_HEADER", unset = "")
  )
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

#' The address a request came from.
#'
#' Behind a proxy every request arrives from the proxy, so a deployment names
#' the header its proxy writes the real address into (CF-Connecting-IP behind
#' Cloudflare). Only name one the proxy always overwrites: a header a caller
#' can set would let anyone pick their own bucket.
atlas_client_ip <- function(req, header = "") {
  if (nzchar(header)) {
    key <- paste0("HTTP_", toupper(gsub("-", "_", header, fixed = TRUE)))
    value <- req[[key]]
    if (length(value) && nzchar(value[[1]])) {
      return(trimws(strsplit(value[[1]], ",", fixed = TRUE)[[1]][[1]]))
    }
  }
  value <- req$REMOTE_ADDR
  if (length(value) && nzchar(value[[1]])) value[[1]] else "unknown"
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

#' What a token is: its tier when live, or why not.
#'
#' Answers are cached by a hash of the token, never the token itself.
#' transport is the call to .org, replaced in tests.
atlas_check_key <- function(key, state, config, now = as.numeric(Sys.time()),
                            transport = atlas_introspect_http) {
  if (!nzchar(config$introspect_url)) {
    return(list(active = FALSE, reason = "not_checked"))
  }
  id <- digest::digest(key, algo = "sha256", serialize = FALSE)
  cached <- state$keys[[id]]
  if (!is.null(cached) && cached$expires > now) {
    return(cached$answer)
  }
  reply <- transport(key, config$introspect_url, config$introspect_secret)
  answer <- if (is.null(reply) || is.null(reply$active)) {
    list(active = FALSE, reason = "unavailable")
  } else if (isTRUE(reply$active) && identical(reply$service, "atlas")) {
    tier <- as.character(reply$tier %||% "standard")
    list(active = TRUE, tier = tier, key_id = as.character(reply$keyId %||% ""))
  } else {
    list(active = FALSE, reason = as.character(reply$reason %||% "unknown"))
  }
  ttl <- if (isTRUE(answer$active)) {
    ATLAS_KEY_TTL_ACTIVE
  } else if (identical(answer$reason, "unavailable")) {
    ATLAS_KEY_TTL_UNAVAILABLE
  } else {
    ATLAS_KEY_TTL_INACTIVE
  }
  assign(id, list(answer = answer, expires = now + ttl), envir = state$keys)
  answer
}

#' Decide one request: let it through, refuse the token, or slow it down.
#'
#' Returns status (NULL to proceed), the headers to send, and a body for a
#' refusal. A token .org rejects is refused outright rather than served at the
#' anonymous rate, so a caller learns their token is wrong instead of quietly
#' getting less. When .org cannot be asked, or tokens cannot be checked on
#' this copy, the caller is served at the anonymous rate.
atlas_access_decision <- function(req, state, config, now = as.numeric(Sys.time()),
                                  transport = atlas_introspect_http) {
  key <- req$HTTP_X_API_KEY
  key <- if (length(key) && nzchar(key[[1]])) key[[1]] else ""
  tier <- "anonymous"
  bucket <- paste0("ip:", atlas_client_ip(req, config$client_ip_header))

  if (nzchar(key)) {
    checked <- atlas_check_key(key, state, config, now, transport)
    if (isTRUE(checked$active)) {
      tier <- if (checked$tier %in% names(config$rates)) checked$tier else "standard"
      bucket <- paste0("key:", checked$key_id)
    } else if (!checked$reason %in% c("unavailable", "not_checked")) {
      return(list(
        status = 401L,
        headers = list(`Cache-Control` = "no-store"),
        body = list(error = "This token is not valid.", reason = checked$reason)
      ))
    }
  }

  if (config$require_token && identical(tier, "anonymous")) {
    return(list(
      status = 401L,
      headers = list(`Cache-Control` = "no-store"),
      body = list(error = "This server needs a token. Send it as an X-API-Key header.")
    ))
  }

  taken <- atlas_rate_take(state, bucket, config$rates[[tier]], now)
  headers <- list(
    `X-RateLimit-Limit` = as.character(taken$limit),
    `X-RateLimit-Remaining` = as.character(taken$remaining),
    `X-Atlas-Tier` = tier
  )
  if (!taken$allowed) {
    headers$`Retry-After` <- as.character(taken$retry_after)
    headers$`Cache-Control` <- "no-store"
    return(list(
      status = 429L,
      headers = headers,
      body = list(
        error = "Too many requests. Slow down, or use a token for a higher limit.",
        retry_after = taken$retry_after
      )
    ))
  }
  list(status = NULL, headers = headers, body = NULL)
}

#' How long a shared cache may keep a response.
#'
#' Everything here changes only when a new release lands, so a CDN in front of
#' the API can answer repeat requests without reaching it. A map requested with
#' its version (?v=) never changes at that address. Rate-limit headers go out
#' with a cached copy too, which only ever over-reports what is left.
atlas_cache_control <- function(path, query = "") {
  if (!startsWith(path, "/api/")) {
    return(NULL)
  }
  if (endsWith(path, "/map.png") && grepl("(^|&)v=", sub("^[?]", "", query))) {
    return("public, max-age=31536000, immutable")
  }
  if (identical(path, "/api/status")) {
    return("public, max-age=60")
  }
  "public, max-age=300"
}
