# Who may read the API and how often: anonymous callers at a modest rate per
# address, signed-in people and token holders at a higher one each, bulk
# tokens higher still, a rejected token refused, and .org being unreachable
# never locking anyone out of reading (only out of downloading).

access_config <- function(anonymous = 3, standard = 10, bulk = 50, require_token = FALSE,
                          introspect = TRUE) {
  list(
    rates = c(anonymous = anonymous, standard = standard, bulk = bulk),
    require_token = require_token,
    introspect_url = if (introspect) "https://org.example/api/service-keys/introspect" else "",
    introspect_secret = if (introspect) "secret" else ""
  )
}

request <- function(ip = "203.0.113.5", key = NULL, ...) {
  req <- list(REMOTE_ADDR = ip, ...)
  if (!is.null(key)) req$HTTP_AUTHORIZATION <- paste("Bearer", key)
  req
}

# A stand-in for mycomap.org that answers from a table and counts calls.
fake_org <- function(answers = list()) {
  calls <- new.env()
  calls$n <- 0
  transport <- function(key, url, secret) {
    calls$n <- calls$n + 1
    calls$last_secret <- secret
    answers[[key]] %||% list(active = FALSE, reason = "unknown")
  }
  list(transport = transport, calls = calls)
}

LIVE <- list(active = TRUE, service = "atlas", keyId = "7", tier = "standard")

test_that("an anonymous caller is served up to the limit, then told to wait", {
  state <- atlas_access_state()
  config <- access_config(anonymous = 3)
  for (i in 1:3) {
    decision <- atlas_access_decision(request(), state, config, now = 1000)
    expect_null(decision$status)
    expect_equal(decision$headers$`X-Atlas-Tier`, "anonymous")
  }
  refused <- atlas_access_decision(request(), state, config, now = 1000)
  expect_equal(refused$status, 429L)
  expect_true(as.numeric(refused$headers$`Retry-After`) > 0)
  expect_equal(refused$headers$`Cache-Control`, "no-store")
})

test_that("the allowance refills with time", {
  state <- atlas_access_state()
  config <- access_config(anonymous = 60)
  for (i in 1:60) atlas_access_decision(request(), state, config, now = 1000)
  expect_equal(atlas_access_decision(request(), state, config, now = 1000)$status, 429L)
  # 60 a minute is one a second.
  expect_null(atlas_access_decision(request(), state, config, now = 1001.5)$status)
})

test_that("each address has its own allowance", {
  state <- atlas_access_state()
  config <- access_config(anonymous = 1)
  expect_null(atlas_access_decision(request("198.51.100.1"), state, config, now = 1)$status)
  expect_equal(atlas_access_decision(request("198.51.100.1"), state, config, now = 1)$status, 429L)
  expect_null(atlas_access_decision(request("198.51.100.2"), state, config, now = 1)$status)
})

test_that("a live token gets its tier's higher limit, counted per token not per address", {
  org <- fake_org(list(good = LIVE))
  state <- atlas_access_state()
  config <- access_config(anonymous = 1, standard = 5)
  for (i in 1:5) {
    decision <- atlas_access_decision(request(paste0("192.0.2.", i), key = "good"), state, config,
                                      now = 1, transport = org$transport)
    expect_null(decision$status)
    expect_equal(decision$headers$`X-Atlas-Tier`, "standard")
    expect_equal(decision$headers$`X-RateLimit-Limit`, "5")
  }
  expect_equal(
    atlas_access_decision(request("192.0.2.99", key = "good"), state, config, now = 1,
                          transport = org$transport)$status,
    429L
  )
})

test_that("a bulk token gets the bulk limit", {
  org <- fake_org(list(big = modifyList(LIVE, list(tier = "bulk"))))
  decision <- atlas_access_decision(request(key = "big"), atlas_access_state(), access_config(bulk = 50),
                                    now = 1, transport = org$transport)
  expect_equal(decision$headers$`X-Atlas-Tier`, "bulk")
  expect_equal(decision$headers$`X-RateLimit-Limit`, "50")
})

test_that("a tier Atlas does not know is served at the standard limit", {
  org <- fake_org(list(odd = modifyList(LIVE, list(tier = "platinum"))))
  decision <- atlas_access_decision(request(key = "odd"), atlas_access_state(), access_config(),
                                    now = 1, transport = org$transport)
  expect_equal(decision$headers$`X-Atlas-Tier`, "standard")
})

test_that("a token mycomap.org rejects is refused with the reason, not served anonymously", {
  for (reason in c("unknown", "pending", "disabled", "revoked", "account_inactive")) {
    org <- fake_org(list(bad = list(active = FALSE, reason = reason)))
    decision <- atlas_access_decision(request(key = "bad"), atlas_access_state(), access_config(),
                                      now = 1, transport = org$transport)
    expect_equal(decision$status, 401L, label = reason)
    expect_equal(decision$body$reason, reason)
  }
})

test_that("a live token for another service is refused", {
  org <- fake_org(list(other = modifyList(LIVE, list(service = "vision"))))
  decision <- atlas_access_decision(request(key = "other"), atlas_access_state(), access_config(),
                                    now = 1, transport = org$transport)
  expect_equal(decision$status, 401L)
})

test_that("when mycomap.org cannot be asked, a token holder is served at the anonymous rate", {
  down <- function(key, url, secret) NULL
  decision <- atlas_access_decision(request(key = "good"), atlas_access_state(), access_config(),
                                    now = 1, transport = down)
  expect_null(decision$status)
  expect_equal(decision$headers$`X-Atlas-Tier`, "anonymous")
})

test_that("a copy of Atlas without introspection settings ignores tokens", {
  org <- fake_org(list(good = LIVE))
  decision <- atlas_access_decision(request(key = "good"), atlas_access_state(),
                                    access_config(introspect = FALSE), now = 1, transport = org$transport)
  expect_null(decision$status)
  expect_equal(decision$headers$`X-Atlas-Tier`, "anonymous")
  expect_equal(org$calls$n, 0)
})

test_that("a token's answer is cached, so .org is asked once per few minutes, not per request", {
  org <- fake_org(list(good = LIVE))
  state <- atlas_access_state()
  config <- access_config(standard = 100)
  for (i in 1:20) atlas_access_decision(request(key = "good"), state, config, now = 1, transport = org$transport)
  expect_equal(org$calls$n, 1)
  atlas_access_decision(request(key = "good"), state, config, now = 1 + ATLAS_KEY_TTL_ACTIVE + 1,
                        transport = org$transport)
  expect_equal(org$calls$n, 2)
  expect_equal(org$calls$last_secret, "secret")
})

test_that("a revoked token stops working once its cached answer expires", {
  answers <- list(tok = LIVE)
  state <- atlas_access_state()
  config <- access_config()
  transport <- function(key, url, secret) answers[[key]]
  expect_null(atlas_access_decision(request(key = "tok"), state, config, now = 1, transport = transport)$status)
  answers$tok <- list(active = FALSE, reason = "revoked")
  expect_null(atlas_access_decision(request(key = "tok"), state, config, now = 2, transport = transport)$status)
  later <- atlas_access_decision(request(key = "tok"), state, config, now = 2 + ATLAS_KEY_TTL_ACTIVE,
                                 transport = transport)
  expect_equal(later$status, 401L)
})

test_that("an outage is never cached, so .org is asked again on the next request", {
  calls <- 0
  down <- function(key, url, secret) {
    calls <<- calls + 1
    NULL
  }
  state <- atlas_access_state()
  expect_equal(atlas_check_key("k", state, access_config(), now = 1, transport = down)$reason, "unavailable")
  atlas_check_key("k", state, access_config(), now = 1, transport = down)
  expect_equal(calls, 2)
  expect_length(ls(state$keys, all.names = TRUE), 0)
  # A transport that throws reads as an outage too.
  boom <- function(key, url, secret) stop("connection reset")
  expect_equal(atlas_check_key("k", state, access_config(), now = 1, transport = boom)$reason, "unavailable")
})

test_that("tokens are never kept in memory as they were sent", {
  org <- fake_org(list(`atlas_secret-token` = LIVE))
  state <- atlas_access_state()
  atlas_check_key("atlas_secret-token", state, access_config(), now = 1, transport = org$transport)
  expect_false("atlas_secret-token" %in% ls(state$keys, all.names = TRUE))
  expect_length(ls(state$keys, all.names = TRUE), 1)
})

test_that("a token-only server refuses anonymous callers and serves token holders", {
  org <- fake_org(list(good = LIVE))
  config <- access_config(require_token = TRUE)
  anonymous <- atlas_access_decision(request(), atlas_access_state(), config, now = 1, transport = org$transport)
  expect_equal(anonymous$status, 401L)
  holder <- atlas_access_decision(request(key = "good"), atlas_access_state(), config, now = 1,
                                  transport = org$transport)
  expect_null(holder$status)
})

test_that("X-Forwarded-For is believed only from this machine, and only its right-most entry", {
  forwarded <- "198.51.100.7, 192.0.2.44"
  expect_equal(atlas_client_ip(list(REMOTE_ADDR = "127.0.0.1", HTTP_X_FORWARDED_FOR = forwarded)), "192.0.2.44")
  expect_equal(atlas_client_ip(list(REMOTE_ADDR = "::1", HTTP_X_FORWARDED_FOR = forwarded)), "192.0.2.44")
  # From anywhere else the header is the caller's own invention.
  expect_equal(atlas_client_ip(list(REMOTE_ADDR = "203.0.113.9", HTTP_X_FORWARDED_FOR = forwarded)), "203.0.113.9")
  expect_equal(atlas_client_ip(list(REMOTE_ADDR = "10.0.0.1", HTTP_X_FORWARDED_FOR = "127.0.0.1")), "10.0.0.1")
  # Loopback without the header is the machine itself.
  expect_equal(atlas_client_ip(list(REMOTE_ADDR = "127.0.0.1")), "127.0.0.1")
  expect_equal(atlas_client_ip(list(REMOTE_ADDR = "127.0.0.1", HTTP_X_FORWARDED_FOR = " , ")), "127.0.0.1")
  expect_equal(atlas_client_ip(list()), "unknown")
})

test_that("a caller cannot pick a fresh allowance by sending X-Forwarded-For", {
  state <- atlas_access_state()
  config <- access_config(anonymous = 1)
  spoof <- function(i) request("203.0.113.9", HTTP_X_FORWARDED_FOR = paste0("198.51.100.", i))
  expect_null(atlas_access_decision(spoof(1), state, config, now = 1)$status)
  expect_equal(atlas_access_decision(spoof(2), state, config, now = 1)$status, 429L)
})

test_that("behind nginx on this machine each visitor has their own allowance", {
  state <- atlas_access_state()
  config <- access_config(anonymous = 1)
  via_nginx <- function(ip) request("127.0.0.1", HTTP_X_FORWARDED_FOR = ip)
  expect_null(atlas_access_decision(via_nginx("198.51.100.1"), state, config, now = 1)$status)
  expect_equal(atlas_access_decision(via_nginx("198.51.100.1"), state, config, now = 1)$status, 429L)
  expect_null(atlas_access_decision(via_nginx("198.51.100.2"), state, config, now = 1)$status)
})

test_that("a token is read from Authorization: Bearer only", {
  expect_equal(atlas_request_token(list(HTTP_AUTHORIZATION = "Bearer atlas_abc")), "atlas_abc")
  expect_equal(atlas_request_token(list(HTTP_AUTHORIZATION = "bearer  atlas_abc ")), "atlas_abc")
  expect_equal(atlas_request_token(list(HTTP_AUTHORIZATION = "Basic dXNlcjpwdw==")), "")
  expect_equal(atlas_request_token(list(HTTP_AUTHORIZATION = "Bearer a b")), "")
  expect_equal(atlas_request_token(list(HTTP_X_API_KEY = "atlas_abc")), "")
  expect_equal(atlas_request_token(list()), "")
})

test_that("a signed-in person gets the standard allowance, counted per person", {
  keys <- test_bridge_keys()
  signin <- signin_config_for(keys)
  cookie <- function(sub) {
    value <- atlas_sign_payload(list(k = "session", sub = sub, name = "A", exp = 1e10), TEST_SECRET)
    paste0(ATLAS_SESSION_COOKIE, "=", value)
  }
  state <- atlas_access_state()
  config <- access_config(anonymous = 1, standard = 3)
  for (i in 1:3) {
    decision <- atlas_access_decision(request(paste0("192.0.2.", i), HTTP_COOKIE = cookie("9")), state, config,
                                      now = 1, signin = signin)
    expect_null(decision$status)
    expect_equal(decision$identity$via, "session")
    expect_equal(decision$headers$`X-Atlas-Tier`, "standard")
  }
  refused <- atlas_access_decision(request("192.0.2.9", HTTP_COOKIE = cookie("9")), state, config,
                                   now = 1, signin = signin)
  expect_equal(refused$status, 429L)
  expect_true(as.numeric(refused$headers$`Retry-After`) > 0)
  # Someone else signed in has their own.
  expect_null(atlas_access_decision(request("192.0.2.9", HTTP_COOKIE = cookie("10")), state, config,
                                    now = 1, signin = signin)$status)
})

test_that("anonymous, signed-in and bulk callers get limits in that order, each refused past its own", {
  keys <- test_bridge_keys()
  signin <- signin_config_for(keys)
  org <- fake_org(list(big = modifyList(LIVE, list(tier = "bulk", keyId = "8"))))
  session <- paste0(ATLAS_SESSION_COOKIE, "=",
                    atlas_sign_payload(list(k = "session", sub = "1", exp = 1e10), TEST_SECRET))
  config <- access_config(anonymous = 2, standard = 4, bulk = 8)
  served <- function(req) {
    state <- atlas_access_state()
    n <- 0
    repeat {
      decision <- atlas_access_decision(req, state, config, now = 1, transport = org$transport, signin = signin)
      if (!is.null(decision$status)) break
      n <- n + 1
    }
    expect_equal(decision$status, 429L)
    expect_false(is.null(decision$headers$`Retry-After`))
    n
  }
  expect_equal(served(request()), 2)
  expect_equal(served(request(HTTP_COOKIE = session)), 4)
  expect_equal(served(request(key = "big")), 8)
})

test_that("an unknown token costs its address an anonymous request before .org is asked", {
  org <- fake_org()
  state <- atlas_access_state()
  config <- access_config(anonymous = 2)
  for (i in 1:2) {
    expect_equal(atlas_access_decision(request(key = paste0("made-up-", i)), state, config, now = 1,
                                       transport = org$transport)$status, 401L)
  }
  flood <- atlas_access_decision(request(key = "made-up-3"), state, config, now = 1, transport = org$transport)
  expect_equal(flood$status, 429L)
  expect_equal(org$calls$n, 2)
})

test_that("answers about the caller are never kept by a shared cache", {
  expect_equal(atlas_cache_control("/api/me"), "private, no-store")
  expect_equal(atlas_cache_control("/api/taxa/X/raster.tif", "algorithm=rf"), "private, no-store")
})

test_that("idle buckets are forgotten so the table cannot grow without bound", {
  state <- atlas_access_state()
  atlas_rate_take(state, "ip:a", 10, now = 0)
  atlas_rate_take(state, "ip:b", 10, now = 900)
  atlas_rate_sweep(state, now = 1000)
  expect_equal(ls(state$buckets), "ip:b")
})

test_that("settings come from the environment, and a URL without a secret checks nothing", {
  with_env(c(ATLAS_RATE_ANONYMOUS = "30", ATLAS_REQUIRE_TOKEN = "true",
             ATLAS_KEY_INTROSPECT_URL = "https://org.example/x", ATLAS_INTROSPECTION_SECRET = NA), {
    config <- atlas_access_config()
    expect_equal(config$rates[["anonymous"]], 30)
    expect_equal(config$rates[["standard"]], ATLAS_RATE_DEFAULTS[["standard"]])
    expect_true(config$require_token)
    expect_equal(config$introspect_url, "")
    expect_match(atlas_access_alerts(config), "^\\[CONFIG-ALERT\\] ATLAS_INTROSPECTION_SECRET")
  })
  # With only the secret, the route is the issuer's.
  with_env(c(ATLAS_INTROSPECTION_SECRET = "shh", ATLAS_KEY_INTROSPECT_URL = NA, ATLAS_SIGNIN_ISSUER = NA), {
    config <- atlas_access_config()
    expect_equal(config$introspect_url, "https://mycomap.org/api/service-keys/introspect")
    expect_equal(config$introspect_secret, "shh")
    expect_length(atlas_access_alerts(config), 0)
  })
  with_env(c(ATLAS_INTROSPECTION_SECRET = "shh", ATLAS_KEY_INTROSPECT_URL = NA,
             ATLAS_SIGNIN_ISSUER = "https://org.example"), {
    expect_equal(atlas_access_config()$introspect_url, "https://org.example/api/service-keys/introspect")
  })
  with_env(c(ATLAS_RATE_ANONYMOUS = "nonsense", ATLAS_REQUIRE_TOKEN = NA), {
    config <- atlas_access_config()
    expect_equal(config$rates[["anonymous"]], ATLAS_RATE_DEFAULTS[["anonymous"]])
    expect_false(config$require_token)
  })
})

test_that("an unreachable mycomap.org reads as no answer rather than an error", {
  testthat::skip_if_not_installed("curl")
  expect_null(atlas_introspect_http("k", "http://127.0.0.1:9/introspect", "s", timeout = 2))
})

test_that("a versioned map may be cached for good, and everything else briefly", {
  expect_equal(atlas_cache_control("/api/taxa/X/map.png", "algorithm=rf&v=2026"), "public, max-age=31536000, immutable")
  expect_equal(atlas_cache_control("/api/taxa/X/map.png", "algorithm=rf"), "public, max-age=300")
  expect_equal(atlas_cache_control("/api/status"), "public, max-age=60")
  expect_equal(atlas_cache_control("/api/models", "grid=draft"), "public, max-age=300")
  expect_null(atlas_cache_control("/"))
})

test_that("an allowlist of * opens the API to every site", {
  expect_equal(atlas_allowed_origin("https://someone.example", allowed = "*"), "*")
  expect_null(atlas_allowed_origin("", allowed = "*"))
})

test_that("a slow answer is built once a minute however many ask, then built again", {
  cache <- new.env(parent = emptyenv())
  built <- 0L
  compute <- function() { built <<- built + 1L; list(grid = "draft", models = data.frame(taxon = c("a", "b"), auc = c(0.7, 0.8))) }
  first <- atlas_memo_json(cache, "k", compute, ttl = 60, now = 1000)
  again <- atlas_memo_json(cache, "k", compute, ttl = 60, now = 1059)
  expect_equal(built, 1L)
  expect_identical(again, first)
  later <- atlas_memo_json(cache, "k", compute, ttl = 60, now = 1061)
  expect_equal(built, 2L)
  # The JSON plumber's unboxed serializer would have written.
  expect_equal(rawToChar(first), as.character(jsonlite::toJSON(compute(), auto_unbox = TRUE)))
  parsed <- jsonlite::fromJSON(rawToChar(later))
  expect_equal(parsed$grid, "draft")
  expect_equal(parsed$models$taxon, c("a", "b"))
})

test_that("the model list still answers JSON with every model through the API", {
  with_data_dir({
    dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE)
    atlas_write_json(list(taxon = "Amanita muscaria", algorithm = "maxnet", presences = 30,
                          auc_mean = 0.7, skill = "passed", built_at = "2026-10-06T00:00:00Z"),
                     atlas_model_path("Amanita muscaria", "draft", ".json"))
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      out <- call_api(api, "/api/models")
      expect_equal(out$status, 200L)
      expect_match(header_values(out, "Content-Type"), "application/json")
      body <- jsonlite::fromJSON(out$body)
      expect_equal(body$grid, "draft")
      expect_equal(body$models$taxon, "Amanita muscaria")
      expect_equal(body$models$skill, "passed")
    })
  })
})

test_that("a versioned ensemble image is kept for good, like a versioned map", {
  expect_equal(atlas_cache_control("/api/taxa/A/ensemble.png", "layer=map&v=2026"),
               "public, max-age=31536000, immutable")
  expect_equal(atlas_cache_control("/api/taxa/A/ensemble.png", "layer=map"), "public, max-age=300")
})

test_that("an error answer is never left cacheable, whatever its path", {
  expect_equal(atlas_settle_cache_control(404L, "public, max-age=300"), "no-store")
  expect_equal(atlas_settle_cache_control(503L, "public, max-age=300"), "no-store")
  expect_equal(atlas_settle_cache_control(200L, "public, max-age=300"), "public, max-age=300")
  expect_null(atlas_settle_cache_control(200L, NULL))
  # Through the API: a missing map is a 404 that says no-store; a found
  # list keeps its public header.
  with_data_dir({
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      missing <- call_api(api, "/api/taxa/Nothing%20here/map.png")
      expect_equal(missing$status, 404L)
      expect_equal(header_values(missing, "Cache-Control"), "no-store")
      broken <- call_api(api, "/api/taxa", query = "limit=abc")
      if (broken$status >= 400L) expect_equal(header_values(broken, "Cache-Control"), "no-store")
      fine <- call_api(api, "/api/algorithms")
      expect_equal(fine$status, 200L)
      expect_equal(header_values(fine, "Cache-Control"), "public, max-age=300")
    })
  })
})

test_that("a Here answer is never kept by a shared cache: it carries the visitor's point", {
  expect_equal(atlas_cache_control("/api/here", "lat=44.0123&lng=-123.0456"), "private, no-store")
  # Other public answers are still kept for five minutes.
  expect_equal(atlas_cache_control("/api/taxa", "q=Amanita"), "public, max-age=300")
})
