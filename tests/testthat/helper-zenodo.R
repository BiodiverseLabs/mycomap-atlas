# A stand-in for Zenodo's deposit API that keeps records in memory. Like the
# real one, a new version may carry the previous version's files (copy_files),
# which the client has to clear.
fake_zenodo <- function(copy_files = TRUE) {
  z <- new.env()
  # Upload failures to stage: name -> how many times to fail. A "stored"
  # failure keeps the file but still answers 502, as a gateway timing out
  # after the server has the bytes does.
  z$fail <- list()
  z$fail_stored <- list()
  z$uploads <- character()
  z$records <- list()
  z$calls <- character()
  z$tokens <- character()
  z$next_id <- 100L
  base <- "https://fake.zenodo/api"
  ok <- function(status, body = NULL) list(status = status, body = body)
  view <- function(r) {
    list(id = r$id, conceptrecid = r$concept, state = r$state, doi = r$doi,
         conceptdoi = if (!is.null(r$doi)) paste0("10.5072/zenodo.", r$concept),
         record_id = r$id, metadata = r$metadata,
         links = list(bucket = paste0(base, "/files/bucket-", r$id),
                      html = paste0("https://fake.zenodo/records/", r$id)))
  }
  new_record <- function(concept = NULL, files = list()) {
    id <- z$next_id
    z$next_id <- z$next_id + 1L
    z$records[[as.character(id)]] <- list(id = id, concept = if (is.null(concept)) id + 5000L else concept, state = "draft",
                                          files = files, metadata = NULL, doi = NULL)
    z$records[[as.character(id)]]
  }
  z$transport <- function(method, url, token, json = NULL, file = NULL) {
    z$tokens <- c(z$tokens, token)
    path <- sub("^https://[^/]+/api", "", url)
    z$calls <- c(z$calls, paste(method, path))
    parts <- strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1]]
    if (method == "POST" && path == "/deposit/depositions") return(ok(201L, view(new_record())))
    if (parts[[1]] == "files") {
      id <- sub("^bucket-", "", parts[[2]])
      r <- z$records[[id]]
      if (r$state != "draft") return(ok(403L, list(message = "published")))
      name <- utils::URLdecode(parts[[3]])
      if ((z$fail[[name]] %||% 0) > 0) {
        z$fail[[name]] <- z$fail[[name]] - 1
        return(ok(502L, list(message = "<html><body>502 Bad Gateway</body></html>")))
      }
      z$uploads <- c(z$uploads, name)
      r$files[[length(r$files) + 1L]] <- list(id = paste0("f", length(r$files) + 1L, "-", id), filename = name,
                                              sha256 = digest::digest(file = file, algo = "sha256"),
                                              checksum = digest::digest(file = file, algo = "md5"))
      z$records[[id]] <- r
      if ((z$fail_stored[[name]] %||% 0) > 0) {
        z$fail_stored[[name]] <- z$fail_stored[[name]] - 1
        return(ok(502L, list(message = "<html><body>502 Bad Gateway</body></html>")))
      }
      return(ok(201L, list(key = name)))
    }
    id <- parts[[3]]
    r <- z$records[[id]]
    if (is.null(r)) return(ok(404L, list(message = "no such deposition")))
    if (length(parts) == 3 && method == "GET") return(ok(200L, c(view(r), list(submitted = r$state == "published"))))
    if (length(parts) == 3 && method == "PUT") {
      r$metadata <- json$metadata
      z$records[[id]] <- r
      return(ok(200L, view(r)))
    }
    if (length(parts) == 3 && method == "DELETE") {
      if (r$state != "draft") return(ok(403L, list(message = "published records cannot be deleted")))
      z$records[[id]] <- NULL
      return(ok(204L))
    }
    if (parts[[4]] == "files" && method == "GET") return(ok(200L, lapply(r$files, function(f) f[c("id", "filename", "checksum")])))
    if (parts[[4]] == "files" && method == "DELETE") {
      r$files <- Filter(function(f) f$id != parts[[5]], r$files)
      z$records[[id]] <- r
      return(ok(204L))
    }
    if (parts[[5]] == "publish") {
      if (is.null(r$metadata$version)) return(ok(400L, list(message = "missing metadata")))
      r$state <- "published"
      r$doi <- paste0("10.5072/zenodo.", r$id)
      z$records[[id]] <- r
      return(ok(202L, view(r)))
    }
    if (parts[[5]] == "newversion") {
      if (r$state != "published") return(ok(400L, list(message = "only a published record gets a new version")))
      draft <- new_record(r$concept, if (copy_files) r$files else list())
      return(ok(201L, list(id = r$id, links = list(latest_draft = paste0(base, "/deposit/depositions/", draft$id)))))
    }
    ok(400L, list(message = paste("unexpected", method, path)))
  }
  z$client <- function(target = "zenodo", waits = c(0, 0, 0)) {
    # No real waiting between retries in tests.
    zen <- atlas_zenodo(target, token = "zenodo-secret-token", transport = z$transport,
                        waits = waits, sleep = function(s) NULL)
    zen
  }
  z
}
