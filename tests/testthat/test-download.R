# Rasters are downloads: only a signed-in person or a live token gets one,
# and the refusal comes before anything is looked up. The public server keeps
# rasters in the store, so a download there is a short-lived presigned link;
# a file on this machine, or a store that is a folder, is sent directly.

NOW <- 1.8e9
TIF_PATH <- "models/draft/amanita-muscaria.tif"
TIF_SHA <- strrep("ab", 32)

# Download services that record what they were asked and never reach AWS.
fake_download <- function(data_dir = tempfile("atlas-data-"), store_uri = "s3://bucket/atlas",
                          files = stats::setNames(TIF_SHA, TIF_PATH)) {
  seen <- new.env()
  seen$lookups <- 0
  seen$presigned <- list()
  services <- atlas_download_services(list(
    data_dir = function() data_dir,
    store_uri = function() store_uri,
    release_files = function(uri, grid) {
      seen$lookups <- seen$lookups + 1
      files
    },
    presign = function(bucket, key, filename, expires) {
      seen$presigned[[length(seen$presigned) + 1L]] <- list(bucket = bucket, key = key,
                                                            filename = filename, expires = expires)
      paste0("https://", bucket, ".s3.example/", key, "?X-Amz-Signature=fake")
    }
  ))
  list(services = services, seen = seen)
}

SESSION <- list(via = "session", tier = "standard", name = "A")
TOKEN <- list(via = "token", tier = "standard")
ANONYMOUS <- list(via = "anonymous", tier = "anonymous")

test_that("an anonymous caller is refused before anything is looked up", {
  fake <- fake_download()
  out <- atlas_raster_response(ANONYMOUS, "Amanita muscaria", "draft", "maxnet", fake$services, new.env())
  expect_equal(out$status, 401L)
  expect_equal(out$body$signIn, "/auth/dev-bridge/start")
  expect_equal(fake$seen$lookups, 0)
  expect_length(fake$seen$presigned, 0)
  expect_equal(atlas_raster_response(NULL, "Amanita muscaria", "draft", "maxnet", fake$services, new.env())$status, 401L)
})

test_that("a signed-in download from S3 is a five-minute presigned link to the object", {
  fake <- fake_download()
  out <- atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", fake$services, new.env(), now = NOW)
  expect_equal(out$status, 302L)
  expect_true(startsWith(out$headers$Location, "https://bucket.s3.example/atlas/objects/ab/"))
  asked <- fake$seen$presigned[[1]]
  expect_equal(asked$bucket, "bucket")
  expect_equal(asked$key, paste0("atlas/", atlas_object_key(TIF_SHA)))
  expect_equal(asked$filename, "amanita-muscaria-maxnet.tif")
  expect_equal(asked$expires, 300)
})

test_that("each algorithm's raster is its own file", {
  fake <- fake_download(files = stats::setNames(TIF_SHA, "models/draft/rf/amanita-muscaria.tif"))
  out <- atlas_raster_response(TOKEN, "Amanita muscaria", "draft", "rf", fake$services, new.env())
  expect_equal(out$status, 302L)
  expect_equal(fake$seen$presigned[[1]]$filename, "amanita-muscaria-rf.tif")
  expect_equal(atlas_raster_response(TOKEN, "Amanita muscaria", "draft", "maxnet", fake$services, new.env())$status, 404L)
})

test_that("the release's file list is read once per few minutes, not per download", {
  fake <- fake_download()
  cache <- new.env()
  for (i in 1:5) atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", fake$services, cache, now = NOW)
  expect_equal(fake$seen$lookups, 1)
  atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", fake$services, cache,
                        now = NOW + ATLAS_MANIFEST_TTL + 1)
  expect_equal(fake$seen$lookups, 2)
})

test_that("a raster the release does not hold is a 404, and an unreachable store a 503", {
  fake <- fake_download(files = stats::setNames(character(), character()))
  expect_equal(atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", fake$services, new.env())$status, 404L)
  broken <- atlas_download_services(list(
    data_dir = function() tempfile(), store_uri = function() "s3://bucket",
    release_files = function(uri, grid) stop("no route to host")
  ))
  out <- suppressMessages(atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", broken, new.env()))
  expect_equal(out$status, 503L)
  none <- fake_download(store_uri = "")
  expect_equal(atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", none$services, new.env())$status, 404L)
})

test_that("a link that cannot be signed is a 503, not a broken redirect", {
  fake <- fake_download()
  fake$services$presign <- function(...) stop("no credentials")
  out <- suppressMessages(atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", fake$services, new.env()))
  expect_equal(out$status, 503L)
})

test_that("a file on this machine is sent as it is", {
  dir <- tempfile("atlas-data-")
  dir.create(file.path(dir, "models", "draft"), recursive = TRUE)
  writeBin(as.raw(1:10), file.path(dir, TIF_PATH))
  fake <- fake_download(data_dir = dir)
  out <- atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", fake$services, new.env())
  expect_equal(out$status, 200L)
  expect_equal(out$file, file.path(dir, TIF_PATH))
  expect_equal(out$headers$`Content-Type`, "image/tiff")
  expect_equal(out$headers$`Content-Disposition`, "attachment; filename=\"amanita-muscaria-maxnet.tif\"")
  expect_length(fake$seen$presigned, 0)
})

test_that("a store that is a folder is read from directly", {
  store <- tempfile("atlas-store-")
  object <- file.path(store, atlas_object_key(TIF_SHA))
  dir.create(dirname(object), recursive = TRUE)
  writeBin(as.raw(1:4), object)
  fake <- fake_download(store_uri = paste0("file://", store))
  out <- atlas_raster_response(SESSION, "Amanita muscaria", "draft", "maxnet", fake$services, new.env())
  expect_equal(out$status, 200L)
  expect_equal(normalizePath(out$file), normalizePath(object))
  expect_length(fake$seen$presigned, 0)
})

test_that("a grid or algorithm that is not one of Atlas's own is refused", {
  fake <- fake_download()
  expect_equal(atlas_raster_response(SESSION, "X", "../../etc", "maxnet", fake$services, new.env())$status, 400L)
  expect_equal(atlas_raster_response(SESSION, "X", "draft", "glm", fake$services, new.env())$status, 400L)
})

test_that("an s3 store's bucket and prefix are read from its URI", {
  expect_equal(atlas_s3_location("s3://bucket/some/prefix"), list(bucket = "bucket", prefix = "some/prefix/"))
  expect_equal(atlas_s3_location("s3://bucket"), list(bucket = "bucket", prefix = ""))
  expect_null(atlas_s3_location("file:///tmp/store"))
  expect_null(atlas_s3_location("/tmp/store"))
})

test_that("the default presigner asks paws for a SigV4 GET link named for saving", {
  asked <- NULL
  client <- list(generate_presigned_url = function(client_method, params, expires_in) {
    asked <<- list(method = client_method, params = params, expires = expires_in)
    "https://signed.example/x"
  })
  expect_equal(atlas_presign_s3("b", "objects/ab/x", "a-maxnet.tif", 300, client = client), "https://signed.example/x")
  expect_equal(asked$method, "get_object")
  expect_equal(asked$params$ResponseContentDisposition, "attachment; filename=\"a-maxnet.tif\"")
  expect_equal(asked$params$ResponseContentType, "image/tiff")
  expect_equal(asked$expires, 300)
})

# ---- through the real API ----------------------------------------------------

download_api <- function(keys, org, fake, env = character()) {
  test_api(c(signin_env(keys), ATLAS_INTROSPECTION_SECRET = "shh", env),
           list(now = function() NOW, introspect = org$transport, download = fake$services))
}

session_cookie <- function() {
  paste0(ATLAS_SESSION_COOKIE, "=", atlas_sign_payload(list(k = "session", sub = "1", exp = NOW + 100), TEST_SECRET))
}

RASTER <- "/api/taxa/Amanita%20muscaria/raster.tif"

test_that("a download is 401 anonymous, and allowed with a session or a live token", {
  keys <- test_bridge_keys()
  fake <- fake_download()
  org <- fake_introspection(list(good = LIVE_TOKEN, gone = list(active = FALSE, reason = "revoked")))
  api <- download_api(keys, org, fake)

  anonymous <- call_api(api, RASTER)
  expect_equal(anonymous$status, 401L)
  expect_equal(jsonlite::fromJSON(anonymous$body)$signIn, "/auth/dev-bridge/start")
  expect_equal(header_values(anonymous, "Cache-Control"), "private, no-store")

  with_session <- call_api(api, RASTER, headers = list(Cookie = session_cookie()))
  expect_equal(with_session$status, 302L)
  expect_true(startsWith(header_values(with_session, "Location"), "https://bucket.s3.example/"))
  expect_equal(header_values(with_session, "Cache-Control"), "private, no-store")

  with_token <- call_api(api, RASTER, headers = list(Authorization = "Bearer good"))
  expect_equal(with_token$status, 302L)

  revoked <- call_api(api, RASTER, headers = list(Authorization = "Bearer gone"))
  expect_equal(revoked$status, 401L)
  expect_length(fake$seen$presigned, 2)
})

test_that("a local file is served with a 200 through the API", {
  keys <- test_bridge_keys()
  dir <- tempfile("atlas-data-")
  dir.create(file.path(dir, "models", "draft"), recursive = TRUE)
  writeBin(as.raw(c(0x49, 0x49, 0x2a, 0x00)), file.path(dir, TIF_PATH))
  fake <- fake_download(data_dir = dir)
  api <- download_api(keys, fake_introspection(), fake)
  out <- call_api(api, RASTER, headers = list(Cookie = session_cookie()))
  expect_equal(out$status, 200L)
  expect_equal(header_values(out, "Content-Type"), "image/tiff")
  # The map's licence travels with the file.
  expect_equal(header_values(out, "Link"), ATLAS_MAP_LICENSE_LINK)
})

test_that("a raster sent as a link to the store says its licence too", {
  keys <- test_bridge_keys()
  fake <- fake_download()
  api <- download_api(keys, fake_introspection(), fake)
  out <- call_api(api, RASTER, headers = list(Cookie = session_cookie()))
  expect_equal(out$status, 302L)
  expect_equal(header_values(out, "Link"), ATLAS_MAP_LICENSE_LINK)
  expect_match(ATLAS_MAP_LICENSE_LINK, "creativecommons.org/licenses/by-sa/4.0/>; rel=\"license\"", fixed = TRUE)
})

test_that("a map image says its licence, anonymous or not", {
  dir <- tempfile("atlas-data-")
  dir.create(file.path(dir, "models", "draft"), recursive = TRUE)
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)), file.path(dir, "models", "draft", "amanita-muscaria.png"))
  with_env(c(ATLAS_DATA_DIR = dir), {
    api <- test_api(c(ATLAS_DATA_DIR = dir))
    out <- call_api(api, "/api/taxa/Amanita%20muscaria/map.png")
    expect_equal(out$status, 200L)
    expect_equal(header_values(out, "Link"), ATLAS_MAP_LICENSE_LINK)
    missing <- call_api(api, "/api/taxa/Nothing%20here/map.png")
    expect_equal(missing$status, 404L)
  })
})

test_that("when mycomap.org cannot be asked a token downloads nothing, and the outage is not cached", {
  keys <- test_bridge_keys()
  fake <- fake_download()
  answers <- list(good = LIVE_TOKEN)
  down <- new.env()
  down$now <- TRUE
  down$n <- 0
  org <- list(transport = function(key, url, secret) {
    down$n <- down$n + 1
    if (down$now) NULL else answers[[key]]
  })
  api <- download_api(keys, org, fake)
  first <- call_api(api, RASTER, headers = list(Authorization = "Bearer good"))
  expect_equal(first$status, 401L)
  down$now <- FALSE
  second <- call_api(api, RASTER, headers = list(Authorization = "Bearer good"))
  expect_equal(second$status, 302L)
  expect_equal(down$n, 2)
})

test_that("a token's answer is cached by its hash, so .org is asked once for many downloads", {
  keys <- test_bridge_keys()
  fake <- fake_download()
  org <- fake_introspection(list(good = LIVE_TOKEN))
  api <- download_api(keys, org, fake)
  for (i in 1:4) expect_equal(call_api(api, RASTER, headers = list(Authorization = "Bearer good"))$status, 302L)
  expect_equal(org$calls$n, 1)
  expect_equal(org$calls$last_secret, "shh")
})

test_that("public routes stay open to anonymous callers", {
  keys <- test_bridge_keys()
  api <- download_api(keys, fake_introspection(), fake_download())
  expect_equal(call_api(api, "/api/algorithms")$status, 200L)
  expect_equal(call_api(api, "/api/openapi.json")$status, 200L)
})

test_that("the API's limits hold per caller kind, with 429 and Retry-After", {
  keys <- test_bridge_keys()
  org <- fake_introspection(list(big = modifyList(LIVE_TOKEN, list(tier = "bulk", keyId = "9"))))
  api <- download_api(keys, org, fake_download(),
                      env = c(ATLAS_RATE_ANONYMOUS = "2", ATLAS_RATE_STANDARD = "3", ATLAS_RATE_BULK = "5"))
  count <- function(headers, remote) {
    n <- 0
    repeat {
      out <- call_api(api, "/api/algorithms", headers = headers, remote = remote)
      if (out$status != 200L) break
      n <- n + 1
    }
    expect_equal(out$status, 429L)
    expect_true(as.numeric(header_values(out, "Retry-After")) > 0)
    n
  }
  expect_equal(count(list(), "198.51.100.1"), 2)
  expect_equal(count(list(Cookie = session_cookie()), "198.51.100.2"), 3)
  expect_equal(count(list(Authorization = "Bearer big"), "198.51.100.3"), 5)
  # A spoofed X-Forwarded-For from a machine that is not the proxy changes nothing.
  expect_equal(call_api(api, "/api/algorithms", headers = list(`X-Forwarded-For` = "192.0.2.1"),
                        remote = "198.51.100.1")$status, 429L)
})
