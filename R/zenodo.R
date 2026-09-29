# A small client for Zenodo's deposit API.
#
# Zenodo keeps every version of a record and gives each two DOIs that matter
# here: a version DOI, fixed to exactly those files forever, and a concept
# DOI shared by all versions, which always resolves to the newest. Atlas cites
# a map by its version DOI and links "the latest" by the concept DOI.
#
# Publishing is permanent: a published version's files can never be changed
# or removed. So every call that creates something leaves a draft, and
# publishing is its own step.
#
# The token comes from ZENODO_TOKEN (scopes deposit:write and
# deposit:actions) and is never written anywhere. The sandbox at
# sandbox.zenodo.org behaves the same and mints test DOIs; use it first.

ATLAS_ZENODO_API <- c(
  zenodo = "https://zenodo.org/api",
  sandbox = "https://sandbox.zenodo.org/api"
)

# Per record, per Zenodo's documentation.
ATLAS_ZENODO_MAX_BYTES <- 50 * 1024^3
ATLAS_ZENODO_MAX_FILES <- 100

#' A connection to Zenodo or its sandbox.
#'
#' transport(method, url, token, json, file) makes one HTTP call and returns
#' list(status, body); tests pass a simulated Zenodo.
atlas_zenodo <- function(target = c("zenodo", "sandbox"),
                         token = Sys.getenv("ZENODO_TOKEN", unset = ""),
                         transport = atlas_zenodo_http) {
  target <- match.arg(target)
  if (!nzchar(token)) {
    stop("set ZENODO_TOKEN to a Zenodo personal access token with deposit:write and ",
         "deposit:actions (for the sandbox, a token made on sandbox.zenodo.org)", call. = FALSE)
  }
  base <- ATLAS_ZENODO_API[[target]]
  call <- function(method, url, json = NULL, file = NULL, expect = c(200L, 201L, 202L, 204L)) {
    if (!grepl("^https?://", url)) url <- paste0(base, url)
    response <- transport(method, url, token, json, file)
    if (!response$status %in% expect) {
      detail <- response$body$message %||% ""
      errors <- response$body$errors
      if (length(errors)) {
        detail <- paste(detail, paste(vapply(errors, function(e) {
          paste0(e$field %||% "", ": ", paste(unlist(e$messages %||% e$message), collapse = " "))
        }, character(1)), collapse = "; "))
      }
      stop("Zenodo answered ", response$status, " to ", method, " ", sub("[?].*$", "", url),
           if (nzchar(detail)) paste0(": ", detail) else "", call. = FALSE)
    }
    response$body
  }
  list(target = target, base = base, call = call)
}

#' One HTTP call to Zenodo, through curl. A file is streamed, not read into
#' memory, since one archive can be gigabytes.
atlas_zenodo_http <- function(method, url, token, json = NULL, file = NULL) {
  handle <- curl::new_handle()
  headers <- c(Authorization = paste("Bearer", token), Accept = "application/json")
  con <- NULL
  if (!is.null(file)) {
    con <- base::file(file, "rb")
    on.exit(close(con), add = TRUE)
    headers[["Content-Type"]] <- "application/octet-stream"
    curl::handle_setopt(
      handle,
      customrequest = method, upload = TRUE,
      infilesize_large = file.info(file)$size,
      readfunction = function(n) readBin(con, raw(), n)
    )
  } else if (!is.null(json)) {
    headers[["Content-Type"]] <- "application/json"
    curl::handle_setopt(
      handle,
      customrequest = method,
      postfields = as.character(jsonlite::toJSON(json, auto_unbox = TRUE, null = "null"))
    )
  } else if (method == "POST") {
    curl::handle_setopt(handle, customrequest = method, postfields = "")
  } else {
    curl::handle_setopt(handle, customrequest = method)
  }
  do.call(curl::handle_setheaders, c(list(handle), as.list(headers)))
  response <- curl::curl_fetch_memory(url, handle = handle)
  text <- rawToChar(response$content)
  body <- if (nzchar(text)) {
    tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) list(message = text))
  } else {
    NULL
  }
  list(status = response$status_code, body = body)
}

#' A new, empty draft record.
atlas_zenodo_create <- function(z) {
  z$call("POST", "/deposit/depositions", json = structure(list(), names = character()), expect = 201L)
}

#' A draft for the next version of a published record. Zenodo may or may not
#' carry the previous version's files into it, so the caller clears it.
atlas_zenodo_new_version <- function(z, deposition_id) {
  made <- z$call("POST", paste0("/deposit/depositions/", deposition_id, "/actions/newversion"),
                 expect = c(200L, 201L))
  draft <- made$links$latest_draft
  if (is.null(draft)) stop("Zenodo made a new version but did not say where its draft is", call. = FALSE)
  z$call("GET", draft)
}

#' Remove every file from a draft.
atlas_zenodo_clear <- function(z, draft) {
  files <- z$call("GET", paste0("/deposit/depositions/", draft$id, "/files"))
  for (f in files %||% list()) {
    z$call("DELETE", paste0("/deposit/depositions/", draft$id, "/files/", f$id), expect = c(200L, 204L))
  }
  invisible(length(files %||% list()))
}

#' Upload one file into a draft's bucket.
atlas_zenodo_upload <- function(z, draft, name, file) {
  bucket <- draft$links$bucket
  if (is.null(bucket)) stop("this Zenodo draft has no bucket to upload into", call. = FALSE)
  z$call("PUT", paste0(bucket, "/", utils::URLencode(name, reserved = TRUE)), file = file,
         expect = c(200L, 201L))
}

atlas_zenodo_set_metadata <- function(z, deposition_id, metadata) {
  z$call("PUT", paste0("/deposit/depositions/", deposition_id), json = list(metadata = metadata))
}

#' Publish a draft: mints its DOI. Cannot be undone.
atlas_zenodo_publish <- function(z, deposition_id) {
  z$call("POST", paste0("/deposit/depositions/", deposition_id, "/actions/publish"),
         expect = c(200L, 202L))
}

#' Throw away an unpublished draft, a new record or a new version alike.
#' Zenodo refuses to delete anything published.
atlas_zenodo_discard <- function(z, deposition_id) {
  z$call("DELETE", paste0("/deposit/depositions/", deposition_id), expect = c(200L, 201L, 204L))
}
