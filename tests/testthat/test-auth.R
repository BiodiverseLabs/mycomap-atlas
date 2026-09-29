# Signing in with a mycomap.org account: only a token .org signed, for this
# site, for this browser's nonce, and fresh, starts a session; a session
# cookie counts only if Atlas signed it and it has not run out; nothing counts
# without the session secret; and a sign-in never redirects off the site.

NOW <- 1.8e9

# ---- tokens ----------------------------------------------------------------

test_that("base64url survives a round trip without padding", {
  for (n in 0:5) {
    bytes <- as.raw(seq_len(n) * 51L %% 256L)
    text <- atlas_b64url_encode(bytes)
    expect_false(grepl("[=+/]", text))
    expect_identical(atlas_b64url_decode(text), bytes)
  }
  expect_null(atlas_b64url_decode("not base64!"))
  expect_null(atlas_b64url_decode("abcde"))
})

test_that("a token mycomap.org signed for this site and this nonce is accepted", {
  keys <- test_bridge_keys()
  nonce <- atlas_new_nonce()
  token <- mint_token(keys$private, good_claims(nonce, NOW))
  checked <- atlas_verify_bridge_token(token, keys$public, TEST_ORIGIN, nonce, now = NOW)
  expect_true(checked$ok)
  expect_equal(checked$claims$sub, "4242")
})

test_that("each kind of bad token is refused for its own reason", {
  keys <- test_bridge_keys()
  other <- test_bridge_keys()
  nonce <- atlas_new_nonce()
  verify <- function(token, n = nonce) atlas_verify_bridge_token(token, keys$public, TEST_ORIGIN, n, now = NOW)$reason

  expect_equal(verify(mint_token(other$private, good_claims(nonce, NOW))), "signature")
  good <- mint_token(keys$private, good_claims(nonce, NOW))
  body <- strsplit(good, ".", fixed = TRUE)[[1]][[1]]
  swapped <- mint_token(keys$private, good_claims(nonce, NOW, sub = "1"))
  expect_equal(verify(paste0(body, ".", strsplit(swapped, ".", fixed = TRUE)[[1]][[2]])), "signature")
  expect_equal(verify(mint_token(keys$private, good_claims(nonce, NOW - 120, exp = NOW - 60))), "expired")
  expect_equal(verify(mint_token(keys$private, good_claims(nonce, NOW + 31, exp = NOW + 91))), "expired")
  expect_equal(verify(mint_token(keys$private, good_claims(nonce, NOW, aud = "https://evil.example"))), "audience")
  expect_equal(verify(mint_token(keys$private, good_claims(nonce, NOW, aud = paste0(TEST_ORIGIN, "/")))), "audience")
  expect_equal(verify(mint_token(keys$private, good_claims(atlas_new_nonce(), NOW))), "nonce")
  expect_equal(verify(mint_token(keys$private, good_claims(nonce, NOW, v = 2))), "malformed")
  expect_equal(verify(mint_token(keys$private, good_claims(nonce, NOW, sub = ""))), "malformed")
  expect_equal(verify(mint_token(keys$private, good_claims(nonce, NOW, exp = "soon"))), "malformed")
  for (junk in c("", "abc", "a.b.c", "a.", ".b", paste0(good, "."), NA_character_)) {
    expect_equal(verify(junk), "malformed", label = junk)
  }
})

test_that("a public key that is not Ed25519 is not accepted as the bridge key", {
  expect_null(atlas_read_bridge_key(""))
  expect_null(atlas_read_bridge_key("not a key"))
  rsa <- openssl::write_pem(as.list(openssl::rsa_keygen(2048))$pubkey)
  expect_null(atlas_read_bridge_key(rsa))
  keys <- test_bridge_keys()
  expect_true(inherits(atlas_read_bridge_key(gsub("\n", "\\n", keys$pem, fixed = TRUE)), "ed25519"))
})

test_that("nonces are fresh and match the pattern mycomap.org accepts", {
  nonces <- replicate(20, atlas_new_nonce())
  expect_true(all(grepl(ATLAS_NONCE_PATTERN, nonces)))
  expect_equal(length(unique(nonces)), 20)
})

test_that("a name that looks like an email is dropped", {
  expect_equal(atlas_clean_name("  Ada Lovelace "), "Ada Lovelace")
  expect_null(atlas_clean_name("ada@example.org"))
  expect_null(atlas_clean_name(""))
  expect_equal(nchar(atlas_clean_name(strrep("a", 300))), 100)
})

# ---- return paths --------------------------------------------------------

test_that("only a path on this site is a place to return to", {
  expect_equal(atlas_safe_return_to("/taxa/Amanita%20muscaria?x=1#m"), "/taxa/Amanita%20muscaria?x=1#m")
  expect_equal(atlas_safe_return_to("/"), "/")
  for (bad in c("//evil.com", "https://evil.com", "/\\evil.com", "\\\\evil.com", "/\t/evil.com",
                "/ok\\..\\x", "javascript:alert(1)", "evil.com", "", "/\n/evil.com",
                strrep("/a", 1200))) {
    expect_equal(atlas_safe_return_to(bad), "/", label = bad)
  }
  expect_equal(atlas_safe_return_to(NULL), "/")
  expect_equal(atlas_safe_return_to(c("/a", "/b")), "/")
})

# ---- signed cookies --------------------------------------------------------

test_that("a signed value reads back only with the same secret, kind and time", {
  value <- atlas_sign_payload(list(k = "session", sub = "1", exp = NOW + 10), TEST_SECRET)
  expect_equal(atlas_read_payload(value, TEST_SECRET, "session", NOW)$sub, "1")
  expect_null(atlas_read_payload(value, paste0(TEST_SECRET, "x"), "session", NOW))
  expect_null(atlas_read_payload(value, TEST_SECRET, "nonce", NOW))
  expect_null(atlas_read_payload(value, TEST_SECRET, "session", NOW + 10))
  expect_null(atlas_read_payload(value, "", "session", NOW))
})

test_that("a tampered session cookie is ignored", {
  keys <- test_bridge_keys()
  config <- signin_config_for(keys)
  value <- atlas_sign_payload(list(k = "session", sub = "1", exp = NOW + 100), TEST_SECRET)
  req <- function(v) list(HTTP_COOKIE = paste0(ATLAS_SESSION_COOKIE, "=", v))
  expect_equal(atlas_request_session(req(value), config, NOW)$sub, "1")

  parts <- strsplit(value, ".", fixed = TRUE)[[1]]
  forged_body <- atlas_b64url_encode(charToRaw('{"k":"session","sub":"2","exp":1900000000}'))
  expect_null(atlas_request_session(req(paste0(forged_body, ".", parts[[2]])), config, NOW))
  flipped <- parts[[2]]
  substr(flipped, 1, 1) <- if (substr(flipped, 1, 1) == "A") "B" else "A"
  expect_null(atlas_request_session(req(paste0(parts[[1]], ".", flipped)), config, NOW))
  expect_null(atlas_request_session(req(parts[[1]]), config, NOW))
  # A nonce cookie's signed value is not a session.
  nonce <- atlas_sign_payload(list(k = "nonce", n = "x", sub = "1", exp = NOW + 100), TEST_SECRET)
  expect_null(atlas_request_session(req(nonce), config, NOW))
})

test_that("an expired session is ignored", {
  keys <- test_bridge_keys()
  config <- signin_config_for(keys)
  value <- atlas_sign_payload(list(k = "session", sub = "1", exp = NOW - 1), TEST_SECRET)
  expect_null(atlas_request_session(list(HTTP_COOKIE = paste0(ATLAS_SESSION_COOKIE, "=", value)), config, NOW))
})

test_that("cookies are parsed from the header, first of a name winning", {
  cookies <- atlas_parse_cookies("a=1; b = two ; a=3; junk; c=x=y")
  expect_equal(cookies$a, "1")
  expect_equal(cookies$b, "two")
  expect_equal(cookies$c, "x=y")
  expect_equal(atlas_parse_cookies(NULL), list())
})

test_that("Atlas's cookies are host-only, secure, http-only and lax", {
  line <- atlas_set_cookie(ATLAS_SESSION_COOKIE, "v", 60)
  expect_true(startsWith(line, "__Host-atlas_session=v;"))
  for (part in c("Max-Age=60", "Path=/", "Secure", "HttpOnly", "SameSite=Lax")) {
    expect_true(grepl(part, line, fixed = TRUE), label = part)
  }
  expect_false(grepl("Domain", line, fixed = TRUE))
})

# ---- configuration -----------------------------------------------------------

test_that("without the session secret nobody is signed in and sign-in is off", {
  keys <- test_bridge_keys()
  config <- signin_config_for(keys, secret = NA)
  expect_false(config$sessions)
  expect_false(config$signin)
  expect_true(any(grepl("^\\[CONFIG-ALERT\\] ATLAS_SESSION_SECRET", config$problems)))
  value <- atlas_sign_payload(list(k = "session", sub = "1", exp = NOW + 100), "")
  expect_null(atlas_request_session(list(HTTP_COOKIE = paste0(ATLAS_SESSION_COOKIE, "=", value)), config, NOW))
  expect_equal(atlas_signin_start(config, "/", NOW)$status, 503L)
  expect_equal(atlas_signin_callback(list(), config, "x", NOW)$status, 503L)
})

test_that("a short session secret counts as none", {
  config <- signin_config_for(test_bridge_keys(), secret = "short")
  expect_false(config$sessions)
  expect_true(any(grepl("shorter than", config$problems)))
})

test_that("each missing setting is named in a config alert, and none when all are set", {
  keys <- test_bridge_keys()
  expect_length(signin_config_for(keys)$problems, 0)
  expect_true(signin_config_for(keys)$signin)
  expect_true(any(grepl("ATLAS_PUBLIC_ORIGIN", signin_config_for(keys, origin = NA)$problems)))
  expect_true(any(grepl("ATLAS_PUBLIC_ORIGIN", signin_config_for(keys, origin = "http://atlas.example.org")$problems)))
  no_key <- with_env(c(signin_env(keys), ATLAS_BRIDGE_PUBLIC_KEY = NA), atlas_signin_config())
  expect_false(no_key$signin)
  expect_true(any(grepl("ATLAS_BRIDGE_PUBLIC_KEY", no_key$problems)))
})

test_that("an origin is scheme, host and port, https unless on this machine", {
  expect_equal(atlas_origin_of("https://Atlas.MycoMap.org/"), "https://atlas.mycomap.org")
  expect_equal(atlas_origin_of("http://localhost:5101"), "http://localhost:5101")
  expect_null(atlas_origin_of("http://atlas.mycomap.org"))
  expect_null(atlas_origin_of("https://atlas.mycomap.org/path"))
  expect_null(atlas_origin_of(""))
})

# ---- the round trip, through the real API ----------------------------------

signin_round_trip <- function(keys, token_for = function(nonce) mint_token(keys$private, good_claims(nonce, NOW)),
                              return_to = "/taxa/Amanita%20muscaria", send_nonce = TRUE,
                              env = signin_env(keys)) {
  api <- test_api(env, list(now = function() NOW))
  start <- call_api(api, "/auth/dev-bridge/start",
                    query = paste0("returnTo=", utils::URLencode(return_to, reserved = TRUE, repeated = TRUE)))
  nonce_cookie <- set_cookie_value(start, ATLAS_NONCE_COOKIE)
  location <- header_values(start, "Location")
  nonce <- sub("^.*[?&]nonce=([^&]+).*$", "\\1", location)
  token <- if (is.function(token_for)) token_for(nonce) else token_for
  headers <- if (send_nonce) list(Cookie = paste0(ATLAS_NONCE_COOKIE, "=", nonce_cookie)) else list()
  back <- call_api(api, "/auth/dev-bridge/callback",
                   query = paste0("token=", utils::URLencode(token, reserved = TRUE, repeated = TRUE)), headers = headers)
  list(api = api, start = start, back = back, nonce = nonce)
}

test_that("start sends the browser to mycomap.org with a nonce and this site as the audience", {
  keys <- test_bridge_keys()
  trip <- signin_round_trip(keys)
  expect_equal(trip$start$status, 302L)
  location <- header_values(trip$start, "Location")
  expect_true(startsWith(location, paste0(TEST_ISSUER, "/auth/dev-bridge/authorize?nonce=")))
  expect_true(grepl("&aud=https%3A%2F%2Fatlas.example.org$", location))
  expect_true(grepl(ATLAS_NONCE_PATTERN, trip$nonce))
  cookie <- header_values(trip$start, "Set-Cookie")
  expect_true(grepl("^__Host-atlas_nonce=.*Max-Age=600; Path=/; Secure; HttpOnly; SameSite=Lax$", cookie))
})

test_that("a valid token signs the person in and returns them where they were", {
  keys <- test_bridge_keys()
  trip <- signin_round_trip(keys)
  expect_equal(trip$back$status, 302L)
  expect_equal(header_values(trip$back, "Location"), "/taxa/Amanita%20muscaria")
  session <- set_cookie_value(trip$back, ATLAS_SESSION_COOKIE)
  expect_true(nzchar(session))
  expect_equal(set_cookie_value(trip$back, ATLAS_NONCE_COOKIE), "")

  me <- call_api(trip$api, "/api/me", headers = list(Cookie = paste0(ATLAS_SESSION_COOKIE, "=", session)))
  body <- jsonlite::fromJSON(me$body)
  expect_true(body$signedIn)
  expect_equal(body$name, "Ada Lovelace")
  expect_equal(body$via, "session")
  # Never the mycomap.org account id.
  expect_false(grepl("4242", me$body, fixed = TRUE))
})

test_that("every bad token is refused with a 400 and no session", {
  keys <- test_bridge_keys()
  other <- test_bridge_keys()
  cases <- list(
    "bad signature" = function(n) mint_token(other$private, good_claims(n, NOW)),
    expired = function(n) mint_token(keys$private, good_claims(n, NOW - 200, exp = NOW - 100)),
    "future iat" = function(n) mint_token(keys$private, good_claims(n, NOW + 120, exp = NOW + 180)),
    "wrong aud" = function(n) mint_token(keys$private, good_claims(n, NOW, aud = "https://vision.example.org")),
    "wrong nonce" = function(n) mint_token(keys$private, good_claims(atlas_new_nonce(), NOW)),
    malformed = "not-a-token",
    "no token" = ""
  )
  for (name in names(cases)) {
    trip <- signin_round_trip(keys, cases[[name]])
    expect_equal(trip$back$status, 400L, label = name)
    expect_null(set_cookie_value(trip$back, ATLAS_SESSION_COOKIE), label = name)
    expect_length(header_values(trip$back, "Location"), 0)
  }
})

test_that("a token is refused when this browser holds no nonce cookie", {
  keys <- test_bridge_keys()
  trip <- signin_round_trip(keys, send_nonce = FALSE)
  expect_equal(trip$back$status, 400L)
  expect_null(set_cookie_value(trip$back, ATLAS_SESSION_COOKIE))
})

test_that("a token is refused with another browser's nonce cookie", {
  keys <- test_bridge_keys()
  api <- test_api(signin_env(keys), list(now = function() NOW))
  mine <- call_api(api, "/auth/dev-bridge/start")
  theirs <- call_api(api, "/auth/dev-bridge/start")
  their_nonce <- sub("^.*nonce=([^&]+).*$", "\\1", header_values(theirs, "Location"))
  token <- mint_token(keys$private, good_claims(their_nonce, NOW))
  back <- call_api(api, "/auth/dev-bridge/callback", query = paste0("token=", token),
                   headers = list(Cookie = paste0(ATLAS_NONCE_COOKIE, "=", set_cookie_value(mine, ATLAS_NONCE_COOKIE))))
  expect_equal(back$status, 400L)
  expect_null(set_cookie_value(back, ATLAS_SESSION_COOKIE))
})

test_that("a sign-in that took longer than ten minutes is refused", {
  keys <- test_bridge_keys()
  config <- signin_config_for(keys)
  start <- atlas_signin_start(config, "/", now = NOW, nonce = atlas_new_nonce())
  cookie <- sub(";.*$", "", sub("^__Host-atlas_nonce=", "", start$headers$`Set-Cookie`))
  nonce <- sub("^.*nonce=([^&]+).*$", "\\1", start$headers$Location)
  later <- NOW + ATLAS_NONCE_SECONDS + 1
  back <- atlas_signin_callback(list(HTTP_COOKIE = paste0(ATLAS_NONCE_COOKIE, "=", cookie)), config,
                                mint_token(keys$private, good_claims(nonce, later)), now = later)
  expect_equal(back$status, 400L)
})

test_that("an open-redirect return path falls back to the home page", {
  keys <- test_bridge_keys()
  for (bad in c("//evil.com", "https://evil.com", "/\\evil.com", "/\t/evil.com")) {
    trip <- signin_round_trip(keys, return_to = bad)
    expect_equal(trip$back$status, 302L, label = bad)
    expect_equal(header_values(trip$back, "Location"), "/", label = bad)
  }
})

test_that("without the session secret the sign-in routes answer 503 and nobody is signed in", {
  keys <- test_bridge_keys()
  env <- signin_env(keys, secret = NA)
  api <- test_api(env, list(now = function() NOW))
  expect_equal(call_api(api, "/auth/dev-bridge/start")$status, 503L)
  expect_equal(call_api(api, "/auth/dev-bridge/callback", query = "token=x")$status, 503L)
  # A cookie signed with an empty secret, or any other, is nobody.
  forged <- atlas_sign_payload(list(k = "session", sub = "1", exp = NOW + 100), "")
  me <- call_api(api, "/api/me", headers = list(Cookie = paste0(ATLAS_SESSION_COOKIE, "=", forged)))
  expect_false(jsonlite::fromJSON(me$body)$signedIn)
  expect_false(jsonlite::fromJSON(me$body)$signInAvailable)
})

test_that("a tampered or expired session cookie is nobody at the API", {
  keys <- test_bridge_keys()
  api <- test_api(signin_env(keys), list(now = function() NOW))
  expired <- atlas_sign_payload(list(k = "session", sub = "1", exp = NOW - 1), TEST_SECRET)
  other_secret <- atlas_sign_payload(list(k = "session", sub = "1", exp = NOW + 100), paste0(TEST_SECRET, "!"))
  for (value in c(expired, other_secret)) {
    me <- call_api(api, "/api/me", headers = list(Cookie = paste0(ATLAS_SESSION_COOKIE, "=", value)))
    expect_false(jsonlite::fromJSON(me$body)$signedIn)
  }
})

test_that("signing out needs a POST from this site's own pages", {
  keys <- test_bridge_keys()
  api <- test_api(signin_env(keys), list(now = function() NOW))
  ok <- call_api(api, "/auth/logout", method = "POST", headers = list(Origin = TEST_ORIGIN))
  expect_equal(ok$status, 200L)
  expect_equal(set_cookie_value(ok, ATLAS_SESSION_COOKIE), "")
  expect_true(grepl("Max-Age=0", header_values(ok, "Set-Cookie")))

  get <- call_api(api, "/auth/logout", method = "GET", headers = list(Origin = TEST_ORIGIN))
  expect_equal(get$status, 405L)
  expect_null(set_cookie_value(get, ATLAS_SESSION_COOKIE))
  for (origin in list("https://evil.example", "https://atlas.example.org.evil.example", NULL)) {
    headers <- if (is.null(origin)) list() else list(Origin = origin)
    refused <- call_api(api, "/auth/logout", method = "POST", headers = headers)
    expect_equal(refused$status, 403L, label = origin %||% "no origin")
    expect_null(set_cookie_value(refused, ATLAS_SESSION_COOKIE))
  }
  expect_equal(atlas_signout(list(REQUEST_METHOD = "GET", HTTP_ORIGIN = TEST_ORIGIN),
                             signin_config_for(keys))$status, 405L)
})

test_that("a signed-out caller is told so, and whether signing in is possible", {
  keys <- test_bridge_keys()
  api <- test_api(signin_env(keys), list(now = function() NOW))
  me <- call_api(api, "/api/me")
  expect_equal(me$status, 200L)
  expect_equal(jsonlite::fromJSON(me$body), list(signedIn = FALSE, signInAvailable = TRUE))
  expect_equal(header_values(me, "Cache-Control"), "private, no-store")
})
