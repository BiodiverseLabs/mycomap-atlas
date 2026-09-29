# Helpers for the sign-in, token and download tests: a throwaway Ed25519 key
# pair standing in for mycomap.org's (never a real key), tokens minted with
# it, and the real plumber file answering requests in-process.

TEST_ORIGIN <- "https://atlas.example.org"
TEST_ISSUER <- "https://org.example"
TEST_SECRET <- strrep("s3cret-for-tests-", 3)

test_bridge_keys <- function() {
  key <- openssl::ed25519_keygen()
  list(private = key, public = as.list(key)$pubkey,
       pem = openssl::write_pem(as.list(key)$pubkey))
}

# A token as .org's signBridgeToken makes it: base64url(JSON), then a
# signature over that base64url text.
mint_token <- function(private, claims) {
  json <- as.character(jsonlite::toJSON(claims, auto_unbox = TRUE, digits = NA))
  body <- atlas_b64url_encode(charToRaw(enc2utf8(json)))
  signature <- openssl::signature_create(charToRaw(body), hash = NULL, key = private)
  paste0(body, ".", atlas_b64url_encode(signature))
}

good_claims <- function(nonce, now, ...) {
  utils::modifyList(list(v = 1, sub = "4242", aud = TEST_ORIGIN, nonce = nonce,
                         iat = now, exp = now + 60, name = "Ada Lovelace"), list(...))
}

signin_env <- function(keys, secret = TEST_SECRET, origin = TEST_ORIGIN, ...) {
  c(ATLAS_PUBLIC_ORIGIN = origin, ATLAS_SIGNIN_ISSUER = TEST_ISSUER,
    ATLAS_BRIDGE_PUBLIC_KEY = gsub("\n", "\\n", keys$pem, fixed = TRUE),
    ATLAS_SESSION_SECRET = secret, ...)
}

# A signin config built from the environment, as the API builds it.
signin_config_for <- function(keys, ...) {
  with_env(signin_env(keys, ...), atlas_signin_config())
}

# ---- the real API, in-process --------------------------------------------

api_file <- function() testthat::test_path("..", "..", "inst", "plumber", "atlas.R")

# The plumber file read with these environment variables and stand-ins for
# the network and the clock.
test_api <- function(env = character(), overrides = list()) {
  envir <- new.env(parent = globalenv())
  envir$atlas_service_overrides <- overrides
  with_env(env, suppressMessages(plumber::pr(api_file(), envir = envir)))
}

# One request through the API. Returns status, headers (a list, repeats kept)
# and the body as text.
call_api <- function(api, path, method = "GET", query = "", headers = list(),
                     remote = "203.0.113.5") {
  req <- new.env()
  req$REQUEST_METHOD <- method
  req$PATH_INFO <- path
  req$QUERY_STRING <- if (nzchar(query)) paste0("?", query) else ""
  req$REMOTE_ADDR <- remote
  req$SERVER_NAME <- "127.0.0.1"
  req$SERVER_PORT <- "5100"
  req$rook.input <- list(read = function(...) raw(), rewind = function() invisible(), read_lines = function() character())
  req$HTTP_HOST <- "atlas.example.org"
  for (name in names(headers)) {
    assign(paste0("HTTP_", toupper(gsub("-", "_", name, fixed = TRUE))), headers[[name]], envir = req)
  }
  out <- suppressMessages(api$call(req))
  body <- out$body
  if (is.raw(body)) body <- rawToChar(body)
  list(status = out$status, headers = out$headers, body = body %||% "")
}

header_values <- function(response, name) {
  unlist(response$headers[tolower(names(response$headers)) == tolower(name)], use.names = FALSE)
}

# The value a Set-Cookie header gives a cookie, or NULL when it sets none.
set_cookie_value <- function(response, name) {
  for (line in header_values(response, "Set-Cookie")) {
    if (startsWith(line, paste0(name, "="))) {
      return(sub(";.*$", "", substring(line, nchar(name) + 2L)))
    }
  }
  NULL
}

# A stand-in for .org's introspection route that answers from a table and
# counts calls. NULL for a key makes it behave as if .org were down.
fake_introspection <- function(answers = list(), down = FALSE) {
  calls <- new.env()
  calls$n <- 0
  transport <- function(key, url, secret) {
    calls$n <- calls$n + 1
    calls$last_secret <- secret
    calls$last_url <- url
    if (down) return(NULL)
    answers[[key]] %||% list(active = FALSE, reason = "unknown")
  }
  list(transport = transport, calls = calls)
}

LIVE_TOKEN <- list(active = TRUE, service = "atlas", keyId = "7", tier = "standard")
