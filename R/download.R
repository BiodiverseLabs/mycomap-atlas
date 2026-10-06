# Downloading a model's raster.
#
# The suitability GeoTIFFs are the one thing Atlas serves only to a signed-in
# person or a live token (R/auth.R, R/access.R). Pages, map PNGs and scores
# stay open.
#
# The public server keeps only the PNGs and JSON of a release on disk; the
# rasters stay in the store, under the hash the current release's manifest
# gives them (R/release.R). So a download is answered with a redirect to a
# presigned S3 link that lasts five minutes. A file on this machine, or a
# store that is a local folder (a laptop, the tests), is sent directly.

# How long a presigned download link works, in seconds.
ATLAS_DOWNLOAD_LINK_SECONDS <- 300

# How long the current release's file list is trusted before it is re-read.
ATLAS_MANIFEST_TTL <- 300

#' The bucket and key prefix of an s3:// store URI, or NULL for any other.
atlas_s3_location <- function(uri) {
  if (!is.character(uri) || length(uri) != 1L || !grepl("^s3://[^/]+", uri)) {
    return(NULL)
  }
  rest <- sub("^s3://", "", uri)
  bucket <- sub("/.*$", "", rest)
  prefix <- if (grepl("/", rest)) sub("^[^/]*/", "", rest) else ""
  prefix <- sub("^/+", "", prefix)
  if (nzchar(prefix) && !grepl("/$", prefix)) prefix <- paste0(prefix, "/")
  list(bucket = bucket, prefix = prefix)
}

#' A presigned GET link for one S3 object, named for saving.
#'
#' Signing happens here, without a call to AWS; the credentials are whatever
#' the machine's default chain provides. Signature version 4, which every
#' region accepts. Replaced in tests, which never reach AWS.
atlas_presign_s3 <- function(bucket, key, filename, expires = ATLAS_DOWNLOAD_LINK_SECONDS,
                             client = NULL) {
  if (is.null(client)) {
    client <- paws.storage::s3(config = list(signature_version = "v4"))
  }
  client$generate_presigned_url(
    client_method = "get_object",
    params = list(
      Bucket = bucket,
      Key = key,
      ResponseContentDisposition = paste0("attachment; filename=\"", filename, "\""),
      ResponseContentType = "image/tiff"
    ),
    expires_in = expires
  )
}

#' The current release's files as a named vector, path -> sha256, or NULL.
atlas_release_files_index <- function(store_uri, grid) {
  manifest <- atlas_current_release(atlas_store(store_uri), grid)
  if (is.null(manifest)) {
    return(NULL)
  }
  paths <- vapply(manifest$files, function(f) as.character(f$path), character(1))
  shas <- vapply(manifest$files, function(f) as.character(f$sha256), character(1))
  stats::setNames(shas, paths)
}

#' The replaceable pieces a download needs: where the store is, how to read
#' its current file list, and how to sign a link. Tests swap them.
atlas_download_services <- function(overrides = list()) {
  defaults <- list(
    data_dir = function() atlas_data_dir(),
    store_uri = function() Sys.getenv("ATLAS_STORE", unset = ""),
    release_files = atlas_release_files_index,
    presign = atlas_presign_s3
  )
  utils::modifyList(defaults, overrides)
}

#' The sha256 of one published path in the current release, read through a
#' cache that keeps each grid's file list for ATLAS_MANIFEST_TTL seconds.
atlas_release_sha <- function(services, grid, path, cache, now = as.numeric(Sys.time())) {
  entry <- cache[[grid]]
  if (is.null(entry) || entry$expires <= now) {
    files <- services$release_files(services$store_uri(), grid)
    entry <- list(files = files, expires = now + ATLAS_MANIFEST_TTL)
    assign(grid, entry, envir = cache)
  }
  if (is.null(entry$files) || !path %in% names(entry$files)) {
    return(NULL)
  }
  entry$files[[path]]
}

# Published maps and rasters are CC BY-SA 4.0: they are derived from
# WorldClim 2.1, which is CC BY-SA 4.0, and ShareAlike carries over. Every map
# image and raster says so in a Link header, so the terms travel with a file
# fetched on its own.
ATLAS_MAP_LICENSE_URL <- "https://creativecommons.org/licenses/by-sa/4.0/"
ATLAS_MAP_LICENSE_LINK <- paste0("<", ATLAS_MAP_LICENSE_URL, ">; rel=\"license\"")

#' Answer GET /api/taxa/<name>/raster.tif.
#'
#' Signed out gets a 401 before anything is looked up. Then, in order: the
#' file on this machine, a store that is a local folder, or a presigned link
#' into S3.
atlas_raster_response <- function(identity, name, grid, algorithm, services, cache,
                                   now = as.numeric(Sys.time())) {
  json <- function(status, body, headers = list()) list(status = status, headers = headers, body = body)
  if (!atlas_is_signed_in(identity)) {
    return(json(401L, list(
      error = "Sign in with your mycomap.org account, or send an API token, to download rasters.",
      signIn = ATLAS_SIGNIN_PATH
    ), list(`WWW-Authenticate` = "Bearer")))
  }
  algorithm <- atlas_request_algorithm(algorithm)
  if (is.null(algorithm)) {
    return(json(400L, list(error = "unknown algorithm")))
  }
  if (!is.character(grid) || length(grid) != 1L || !grepl("^[a-z][a-z0-9_]{0,31}$", grid)) {
    return(json(400L, list(error = "unknown grid")))
  }
  path <- atlas_model_relpaths(name, grid, algorithm, ".tif")
  slug <- sub("[.]tif$", "", basename(path))
  if (!nzchar(slug)) {
    return(json(404L, list(error = "no raster for this taxon")))
  }
  filename <- paste0(slug, "-", algorithm, ".tif")
  file_headers <- list(
    `Content-Type` = "image/tiff",
    `Content-Disposition` = paste0("attachment; filename=\"", filename, "\""),
    Link = ATLAS_MAP_LICENSE_LINK
  )

  local <- file.path(services$data_dir(), path)
  if (file.exists(local)) {
    return(list(status = 200L, headers = file_headers, file = local))
  }

  store_uri <- services$store_uri()
  if (!nzchar(store_uri)) {
    return(json(404L, list(error = "no raster for this taxon on this server")))
  }
  sha <- tryCatch(atlas_release_sha(services, grid, path, cache, now), error = function(e) {
    message("[download] could not read the current release: ", conditionMessage(e))
    FALSE
  })
  if (isFALSE(sha)) {
    return(json(503L, list(error = "the release store cannot be reached; try again shortly")))
  }
  if (is.null(sha) || !grepl("^[0-9a-f]{64}$", sha)) {
    return(json(404L, list(error = "no raster for this taxon in the current release")))
  }
  key <- atlas_object_key(sha)

  s3 <- atlas_s3_location(store_uri)
  if (is.null(s3)) {
    stored <- file.path(sub("^file://", "", store_uri), key)
    if (!file.exists(stored)) {
      return(json(404L, list(error = "no raster for this taxon in the current release")))
    }
    return(list(status = 200L, headers = file_headers, file = stored))
  }
  url <- tryCatch(
    services$presign(s3$bucket, paste0(s3$prefix, key), filename, ATLAS_DOWNLOAD_LINK_SECONDS),
    error = function(e) {
      message("[download] could not sign a link: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.character(url) || length(url) != 1L || !startsWith(url, "https://")) {
    return(json(503L, list(error = "a download link could not be made; try again shortly")))
  }
  list(status = 302L, headers = list(Location = url, Link = ATLAS_MAP_LICENSE_LINK), body = "")
}
