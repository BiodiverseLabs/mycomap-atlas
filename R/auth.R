# Signing in with a mycomap.org account.
#
# Atlas has no accounts of its own. mycomap.org vouches for a person through
# its sign-in bridge, and Atlas keeps a session of its own after that:
#
#   Atlas GET /auth/dev-bridge/start     makes a nonce, keeps it in a short-
#                                        lived cookie in this browser, and
#                                        sends the browser to mycomap.org
#   .org  GET /auth/dev-bridge/authorize signs {sub, aud, nonce, iat, exp,
#                                        name?} with its PRIVATE key and sends
#                                        the browser back
#   Atlas GET /auth/dev-bridge/callback  verifies the token with the PUBLIC
#                                        key, checks it was made for this site
#                                        and this browser's nonce, and sets
#                                        Atlas's own session cookie
#
# The format is .org's (artifacts/api-server/src/auth/devBridge.ts there):
# base64url(JSON) "." base64url(Ed25519 signature over that base64url text),
# valid for 60 s. Atlas holds only the public key, so it can check a token but
# never make one; a leaked Atlas box cannot sign anyone in anywhere.
#
# The session is stateless: a cookie holding who the person is and until
# when, with an HMAC-SHA256 over it keyed by ATLAS_SESSION_SECRET. Without
# that secret nothing is treated as signed in and the sign-in routes answer
# 503. No cookie is shared with mycomap.org.
#
# Signing in unlocks downloads and a higher API allowance. Everything the
# pages need stays public.

ATLAS_SESSION_COOKIE <- "__Host-atlas_session"
ATLAS_NONCE_COOKIE <- "__Host-atlas_nonce"

# A session lasts two weeks; a sign-in has ten minutes to come back from .org.
ATLAS_SESSION_SECONDS <- 14 * 24 * 3600
ATLAS_NONCE_SECONDS <- 600

# Where a signed-out caller is sent to sign in.
ATLAS_SIGNIN_PATH <- "/auth/dev-bridge/start"

# .org's NONCE_PATTERN: 22 to 128 base64url characters.
ATLAS_NONCE_PATTERN <- "^[A-Za-z0-9_-]{22,128}$"

# The shortest session secret accepted. A shorter one is treated as unset.
ATLAS_SESSION_SECRET_MIN <- 32

# ---- encoding ------------------------------------------------------------

#' base64url without padding, as .org writes it.
atlas_b64url_encode <- function(bytes) {
  text <- openssl::base64_encode(bytes)
  sub("=+$", "", chartr("+/", "-_", text))
}

#' Decode base64url, or NULL when the text is not base64url.
atlas_b64url_decode <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) ||
      !grepl("^[A-Za-z0-9_-]*$", text) || nchar(text) %% 4L == 1L) {
    return(NULL)
  }
  padded <- chartr("-_", "+/", text)
  padded <- paste0(padded, strrep("=", (4L - nchar(padded) %% 4L) %% 4L))
  tryCatch(openssl::base64_decode(padded), error = function(e) NULL)
}

#' Compare two secrets in time that does not depend on where they differ.
atlas_constant_time_equal <- function(a, b) {
  if (is.character(a)) a <- charToRaw(enc2utf8(a))
  if (is.character(b)) b <- charToRaw(enc2utf8(b))
  if (!is.raw(a) || !is.raw(b) || length(a) != length(b) || !length(a)) {
    return(FALSE)
  }
  !any(as.logical(xor(a, b)))
}

atlas_hmac <- function(text, secret) {
  as.raw(openssl::sha256(charToRaw(enc2utf8(text)), key = secret))
}

#' A payload signed with the session secret: base64url(JSON) "." base64url(HMAC).
atlas_sign_payload <- function(payload, secret) {
  json <- as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, digits = NA))
  body <- atlas_b64url_encode(charToRaw(enc2utf8(json)))
  paste0(body, ".", atlas_b64url_encode(atlas_hmac(body, secret)))
}

#' The payload of a signed value, or NULL when it was not signed with this
#' secret, is of another kind, or has expired.
atlas_read_payload <- function(value, secret, kind, now = as.numeric(Sys.time())) {
  if (!nzchar(secret %||% "") || !is.character(value) || length(value) != 1L ||
      is.na(value) || nchar(value) > 4096L) {
    return(NULL)
  }
  parts <- strsplit(value, ".", fixed = TRUE)[[1]]
  if (length(parts) != 2L || !nzchar(parts[[1]]) || endsWith(value, ".")) {
    return(NULL)
  }
  mac <- atlas_b64url_decode(parts[[2]])
  if (is.null(mac) || !atlas_constant_time_equal(mac, atlas_hmac(parts[[1]], secret))) {
    return(NULL)
  }
  bytes <- atlas_b64url_decode(parts[[1]])
  payload <- tryCatch({
    text <- rawToChar(bytes)
    Encoding(text) <- "UTF-8"
    jsonlite::fromJSON(text, simplifyVector = FALSE)
  }, error = function(e) NULL)
  if (!is.list(payload) || !identical(payload$k, kind) ||
      !is.numeric(payload$exp) || length(payload$exp) != 1L || payload$exp <= now) {
    return(NULL)
  }
  payload
}

# ---- configuration -------------------------------------------------------

#' An origin (scheme, host, port) from a URL written without a path, or NULL.
#'
#' https everywhere; http only on this machine, for development. A cookie
#' named __Host- is only kept over a secure connection, so http elsewhere
#' could never hold a session.
atlas_origin_of <- function(url) {
  url <- trimws(url %||% "")
  pattern <- "^(https?)://([A-Za-z0-9.-]+|\\[[0-9A-Fa-f:]+\\])(:[0-9]{1,5})?/?$"
  if (!grepl(pattern, url)) {
    return(NULL)
  }
  scheme <- tolower(sub(pattern, "\\1", url))
  host <- tolower(sub(pattern, "\\2", url))
  port <- sub(pattern, "\\3", url)
  if (identical(scheme, "http") && !host %in% c("localhost", "127.0.0.1", "[::1]")) {
    return(NULL)
  }
  paste0(scheme, "://", host, port)
}

#' The bridge's public key from PEM text, or NULL unless it is Ed25519. Env
#' files often carry a PEM with literal "\n" for its line breaks.
atlas_read_bridge_key <- function(pem) {
  text <- gsub("\\n", "\n", trimws(pem %||% ""), fixed = TRUE)
  if (!nzchar(text)) {
    return(NULL)
  }
  key <- tryCatch(openssl::read_pubkey(text), error = function(e) NULL)
  if (inherits(key, "ed25519")) key else NULL
}

#' Sign-in settings from the environment.
#'
#' sessions: a session cookie can be read (the secret is set).
#' signin: the whole round trip through mycomap.org can run.
#' problems: [CONFIG-ALERT] lines for whatever is missing, printed at start.
atlas_signin_config <- function() {
  origin_text <- Sys.getenv("ATLAS_PUBLIC_ORIGIN", unset = "")
  issuer_text <- Sys.getenv("ATLAS_SIGNIN_ISSUER", unset = "")
  if (!nzchar(issuer_text)) issuer_text <- "https://mycomap.org"
  secret <- Sys.getenv("ATLAS_SESSION_SECRET", unset = "")
  pem <- Sys.getenv("ATLAS_BRIDGE_PUBLIC_KEY", unset = "")

  problems <- character()
  alert <- function(...) problems <<- c(problems, paste0("[CONFIG-ALERT] ", ...))

  if (!nzchar(secret)) {
    alert("ATLAS_SESSION_SECRET is not set: sign-in is off and nobody is treated as signed in.")
  } else if (nchar(secret) < ATLAS_SESSION_SECRET_MIN) {
    alert("ATLAS_SESSION_SECRET is shorter than ", ATLAS_SESSION_SECRET_MIN,
          " characters: it is ignored, sign-in is off and nobody is treated as signed in.")
    secret <- ""
  }
  origin <- atlas_origin_of(origin_text)
  if (is.null(origin)) {
    alert(if (nzchar(origin_text)) {
      paste0("ATLAS_PUBLIC_ORIGIN \"", origin_text, "\" is not an https origin such as https://atlas.mycomap.org")
    } else {
      "ATLAS_PUBLIC_ORIGIN is not set"
    }, ": sign-in is off.")
  }
  issuer <- atlas_origin_of(issuer_text)
  if (is.null(issuer)) {
    alert("ATLAS_SIGNIN_ISSUER \"", issuer_text, "\" is not an https origin: sign-in is off.")
  }
  key <- atlas_read_bridge_key(pem)
  if (is.null(key)) {
    alert(if (nzchar(pem)) {
      "ATLAS_BRIDGE_PUBLIC_KEY is not an Ed25519 public key in PEM form"
    } else {
      "ATLAS_BRIDGE_PUBLIC_KEY is not set"
    }, ": sign-in is off.")
  }

  sessions <- nzchar(secret)
  list(
    origin = origin,
    issuer = issuer,
    public_key = key,
    secret = secret,
    sessions = sessions,
    signin = sessions && !is.null(origin) && !is.null(issuer) && !is.null(key),
    problems = problems
  )
}

# ---- tokens from mycomap.org ---------------------------------------------

#' A fresh nonce: 24 random bytes as 32 base64url characters, which .org's
#' NONCE_PATTERN accepts.
atlas_new_nonce <- function() {
  atlas_b64url_encode(openssl::rand_bytes(24))
}

#' Check a sign-in token from mycomap.org, the way .org's verifyBridgeToken
#' does: the signature first, then the claims, then the time, the audience
#' and the nonce. Returns list(ok = TRUE, claims) or list(ok = FALSE, reason).
atlas_verify_bridge_token <- function(token, public_key, aud, nonce,
                                      now = as.numeric(Sys.time())) {
  fail <- function(reason) list(ok = FALSE, reason = reason)
  if (!is.character(token) || length(token) != 1L || is.na(token) || nchar(token) > 4096L) {
    return(fail("malformed"))
  }
  parts <- strsplit(token, ".", fixed = TRUE)[[1]]
  if (length(parts) != 2L || !nzchar(parts[[1]]) || !nzchar(parts[[2]]) || endsWith(token, ".")) {
    return(fail("malformed"))
  }
  signature <- atlas_b64url_decode(parts[[2]])
  valid <- !is.null(signature) && !is.null(public_key) && tryCatch(
    isTRUE(openssl::signature_verify(charToRaw(parts[[1]]), signature, hash = NULL, pubkey = public_key)),
    error = function(e) FALSE
  )
  if (!valid) {
    return(fail("signature"))
  }

  claims <- tryCatch({
    text <- rawToChar(atlas_b64url_decode(parts[[1]]))
    Encoding(text) <- "UTF-8"
    jsonlite::fromJSON(text, simplifyVector = FALSE)
  }, error = function(e) NULL)
  one <- function(x, test) !is.null(x) && length(x) == 1L && test(x)
  if (!is.list(claims) || is.null(names(claims)) ||
      !one(claims$v, is.numeric) || claims$v != 1 ||
      !one(claims$sub, is.character) || !nzchar(claims$sub) ||
      !one(claims$exp, is.numeric) ||
      !one(claims$nonce, is.character) ||
      (!is.null(claims$iat) && !one(claims$iat, is.numeric))) {
    return(fail("malformed"))
  }
  if (claims$exp < now || (!is.null(claims$iat) && claims$iat > now + 30)) {
    return(fail("expired"))
  }
  if (!one(claims$aud, is.character) || !identical(claims$aud, aud)) {
    return(fail("audience"))
  }
  if (!one(nonce, is.character) || !atlas_constant_time_equal(claims$nonce, nonce)) {
    return(fail("nonce"))
  }
  list(ok = TRUE, claims = claims)
}

#' The display name a token carried, kept only if it is plainly a name.
atlas_clean_name <- function(name) {
  if (!is.character(name) || length(name) != 1L || is.na(name)) {
    return(NULL)
  }
  name <- trimws(gsub("[[:cntrl:]]", "", name))
  if (!nzchar(name) || grepl("@", name, fixed = TRUE)) {
    return(NULL)
  }
  substr(name, 1L, 100L)
}

# ---- cookies and paths ---------------------------------------------------

#' Cookies from a Cookie header. The first of a repeated name wins.
atlas_parse_cookies <- function(header) {
  out <- list()
  if (is.null(header) || !length(header) || is.na(header[[1]]) || !nzchar(header[[1]])) {
    return(out)
  }
  for (part in strsplit(header[[1]], ";", fixed = TRUE)[[1]]) {
    at <- regexpr("=", part, fixed = TRUE)
    if (at < 1L) next
    name <- trimws(substr(part, 1L, at - 1L))
    if (nzchar(name) && is.null(out[[name]])) {
      out[[name]] <- trimws(substring(part, at + 1L))
    }
  }
  out
}

#' A Set-Cookie value for one of Atlas's cookies. The __Host- prefix makes a
#' browser refuse it unless it is Secure, host-only and on Path=/, so no other
#' mycomap.org site can set or overwrite it. Lax lets it ride the top-level
#' redirect back from mycomap.org and nothing cross-site besides.
atlas_set_cookie <- function(name, value, max_age) {
  paste0(name, "=", value, "; Max-Age=", as.integer(max_age),
         "; Path=/; Secure; HttpOnly; SameSite=Lax")
}

atlas_clear_cookie <- function(name) atlas_set_cookie(name, "", 0)

#' Where to send a person after signing in: a path on this site, else "/".
#'
#' The same rule as .org's sanitizeReturnTo. One leading "/" and not two,
#' which a browser reads as another host; no backslash, which browsers treat
#' as a slash; no control character, which browsers strip ("/\t/evil.com"
#' becomes "//evil.com").
atlas_safe_return_to <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !nzchar(value) || nchar(value) > 2000L) {
    return("/")
  }
  if (!startsWith(value, "/") || startsWith(value, "//") ||
      grepl("[\\\\[:cntrl:]]", value) || grepl("\x7f", value, fixed = TRUE)) {
    return("/")
  }
  value
}

# ---- sessions ------------------------------------------------------------

#' The signed-in person a request carries, or NULL.
atlas_request_session <- function(req, config, now = as.numeric(Sys.time())) {
  if (!isTRUE(config$sessions)) {
    return(NULL)
  }
  value <- atlas_parse_cookies(req$HTTP_COOKIE)[[ATLAS_SESSION_COOKIE]]
  payload <- atlas_read_payload(value, config$secret, "session", now)
  if (is.null(payload) || !is.character(payload$sub) || length(payload$sub) != 1L ||
      !nzchar(payload$sub)) {
    return(NULL)
  }
  list(sub = payload$sub, name = atlas_clean_name(payload$name))
}

#' Whether an identity may download: a session or a live token.
atlas_is_signed_in <- function(identity) {
  !is.null(identity) && identity$via %in% c("session", "token")
}

# ---- routes ----------------------------------------------------------------
#
# Each returns list(status, headers, body); atlas_send() writes it out. A
# body that is a list goes out as JSON, a string as plain text.

atlas_signin_unavailable <- function() {
  list(
    status = 503L,
    headers = list(`Cache-Control` = "no-store"),
    body = "Signing in is not set up on this server."
  )
}

#' GET /auth/dev-bridge/start: remember a nonce in this browser, go to .org.
atlas_signin_start <- function(config, return_to = "/", now = as.numeric(Sys.time()),
                               nonce = atlas_new_nonce()) {
  if (!isTRUE(config$signin)) {
    return(atlas_signin_unavailable())
  }
  cookie <- atlas_sign_payload(list(
    k = "nonce",
    n = nonce,
    r = atlas_safe_return_to(return_to),
    exp = now + ATLAS_NONCE_SECONDS
  ), config$secret)
  location <- paste0(
    config$issuer, "/auth/dev-bridge/authorize?nonce=", nonce,
    "&aud=", utils::URLencode(config$origin, reserved = TRUE)
  )
  list(
    status = 302L,
    headers = list(
      Location = location,
      `Set-Cookie` = atlas_set_cookie(ATLAS_NONCE_COOKIE, cookie, ATLAS_NONCE_SECONDS),
      `Cache-Control` = "no-store"
    ),
    body = ""
  )
}

#' GET /auth/dev-bridge/callback: check .org's token, start a session.
#'
#' The nonce cookie is cleared whatever happens, so a nonce is used once. A
#' refusal is a 400 with a short message, never a redirect.
atlas_signin_callback <- function(req, config, token, now = as.numeric(Sys.time())) {
  if (!isTRUE(config$signin)) {
    return(atlas_signin_unavailable())
  }
  clear <- atlas_clear_cookie(ATLAS_NONCE_COOKIE)
  refuse <- function(message) {
    list(status = 400L, headers = list(`Set-Cookie` = clear, `Cache-Control` = "no-store"),
         body = message)
  }
  started <- atlas_read_payload(
    atlas_parse_cookies(req$HTTP_COOKIE)[[ATLAS_NONCE_COOKIE]], config$secret, "nonce", now
  )
  if (is.null(started) || !is.character(started$n) || length(started$n) != 1L) {
    return(refuse("This sign-in expired or was started in another browser. Please sign in again."))
  }
  checked <- atlas_verify_bridge_token(token, config$public_key, config$origin, started$n, now)
  if (!isTRUE(checked$ok)) {
    message("[signin] refused a token from ", config$issuer, ": ", checked$reason)
    return(refuse(if (identical(checked$reason, "expired")) {
      "This sign-in took too long. Please sign in again."
    } else {
      "Sign-in failed. Please sign in again."
    }))
  }
  session <- Filter(Negate(is.null), list(
    k = "session",
    sub = checked$claims$sub,
    name = atlas_clean_name(checked$claims$name),
    iat = now,
    exp = now + ATLAS_SESSION_SECONDS
  ))
  list(
    status = 302L,
    headers = list(
      Location = atlas_safe_return_to(started$r),
      `Set-Cookie` = clear,
      `Set-Cookie` = atlas_set_cookie(ATLAS_SESSION_COOKIE, atlas_sign_payload(session, config$secret),
                                      ATLAS_SESSION_SECONDS),
      `Cache-Control` = "no-store"
    ),
    body = ""
  )
}

#' POST /auth/logout: clear the session cookie.
#'
#' Only a POST from a page on this site: another site could otherwise sign a
#' visitor out with a link or a form.
atlas_signout <- function(req, config) {
  if (!identical(req$REQUEST_METHOD, "POST")) {
    return(list(status = 405L, headers = list(Allow = "POST", `Cache-Control` = "no-store"),
                body = "Sign out with a POST."))
  }
  if (is.null(config$origin)) {
    return(atlas_signin_unavailable())
  }
  origin <- req$HTTP_ORIGIN
  if (is.null(origin) || !length(origin) || !identical(as.character(origin[[1]]), config$origin)) {
    return(list(status = 403L, headers = list(`Cache-Control` = "no-store"),
                body = "Sign out from this site's own pages."))
  }
  list(
    status = 200L,
    headers = list(`Set-Cookie` = atlas_clear_cookie(ATLAS_SESSION_COOKIE), `Cache-Control` = "no-store"),
    body = list(signedIn = FALSE)
  )
}

#' GET /api/me: whether this caller is signed in, for the page header. Never
#' the .org account id.
atlas_me <- function(identity, config) {
  available <- isTRUE(config$signin)
  if (!atlas_is_signed_in(identity)) {
    return(list(signedIn = FALSE, signInAvailable = available))
  }
  Filter(Negate(is.null), list(
    signedIn = TRUE,
    name = identity$name,
    via = identity$via,
    tier = identity$tier,
    signInAvailable = available
  ))
}

#' Write a route's list(status, headers, body[, file]) to plumber's response.
atlas_send <- function(res, out) {
  res$status <- out$status
  for (i in seq_along(out$headers)) {
    res$setHeader(names(out$headers)[[i]], out$headers[[i]])
  }
  if (!is.null(out$file)) {
    res$body <- readBin(out$file, "raw", file.info(out$file)$size)
  } else if (is.list(out$body)) {
    res$setHeader("Content-Type", "application/json")
    res$body <- as.character(jsonlite::toJSON(out$body, auto_unbox = TRUE))
  } else {
    if (nzchar(out$body %||% "")) res$setHeader("Content-Type", "text/plain; charset=utf-8")
    res$body <- out$body %||% ""
  }
  res
}
