# Drafts that publish themselves.
#
# Every archive version stops at a draft on Zenodo (R/archive.R). Steve decided
# (2026-11-19) that a draft publishes itself a few days after it is made,
# unless a person deletes it on zenodo.org first: the days between are the
# time to look at it, and deleting it is how to say no.
#
# Publishing is permanent, so this is run often and decides afresh each time,
# from the ledger and from what Zenodo says now. For each series' waiting
# draft:
#
#   deleted on zenodo.org       the ledger marks the version discarded
#   published there by a person the ledger records its DOI
#   older than the grace period published (atlas_archive_publish), but only
#                               if it reads back as exactly what was made:
#                               not submitted, its version label, title and
#                               description, and its files by name and MD5,
#                               all as the ledger recorded them
#   younger                     left alone, with the date it will publish
#
# Two more refusals, because some versions need a person's eye that a check
# against the ledger cannot give. The description a version was given on
# zenodo.org may carry text a person added by hand: Steve added the paragraph
# on the 76 erroneous records to version 23463939 on 2026-10-21, and it was put
# into 24214060 by hand because the generated description leaves it out. So a
# draft is refused when the newest published version's description on Zenodo
# is not the one the code wrote for it, or when the ledger does not record
# what the code wrote (every version made before this file). A person then
# reads both and publishes with archive-publish, or deletes the draft.
#
# Anything refused stays a draft and is said in the output, every run, so a
# scheduler marks the run failed until a person acts. The Zenodo token is
# only ever sent in the request header (R/zenodo.R).

# Days a draft waits before it publishes itself (Steve, 2026-11-19).
ATLAS_ARCHIVE_PUBLISH_AFTER_DAYS <- 3

#' The grace period in days, from ATLAS_ZENODO_PUBLISH_AFTER_DAYS: a number of
#' days, 1 or more, or "off" to never publish (deleted and hand-published
#' drafts are still recorded). Unset is the default.
atlas_archive_publish_after_days <- function(value = Sys.getenv("ATLAS_ZENODO_PUBLISH_AFTER_DAYS", unset = "")) {
  value <- trimws(as.character(value %||% ""))
  if (!nzchar(value)) return(ATLAS_ARCHIVE_PUBLISH_AFTER_DAYS)
  if (identical(tolower(value), "off")) return(Inf)
  days <- suppressWarnings(as.numeric(value))
  # Under a day leaves no time to look at a draft before it is permanent.
  if (is.na(days) || days < 1) {
    stop("the grace period must be a number of days, 1 or more, or off: not ", value, call. = FALSE)
  }
  days
}

atlas_archive_time <- function(x) {
  if (is.null(x) || !nzchar(as.character(x))) return(NULL)
  t <- as.POSIXct(as.character(x), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(t)) NULL else t
}

atlas_archive_stamp <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' The text a reader sees in a description: Zenodo may store the HTML it was
#' sent differently (entities, tags, line breaks), so descriptions are compared
#' as this.
atlas_archive_reader_text <- function(x) {
  x <- gsub("<[^>]*>", " ", as.character(x %||% ""))
  for (pattern in c("&#[0-9]+;", "&#[xX][0-9a-fA-F]+;")) {
    m <- gregexpr(pattern, x)
    regmatches(x, m) <- lapply(regmatches(x, m), function(s) vapply(s, function(e) {
      digits <- substr(e, 3L, nchar(e) - 1L)
      code <- if (startsWith(digits, "x") || startsWith(digits, "X")) strtoi(substring(digits, 2L), 16L) else as.integer(digits)
      intToUtf8(code)
    }, character(1), USE.NAMES = FALSE))
  }
  named <- c("&lt;" = "<", "&gt;" = ">", "&quot;" = "\"", "&apos;" = "'", "&nbsp;" = " ")
  for (n in names(named)) x <- gsub(n, named[[n]], x, fixed = TRUE)
  x <- gsub("&amp;", "&", x, fixed = TRUE)
  trimws(gsub("[[:space:]]+", " ", x))
}

#' Where two texts first differ, briefly, for a refusal.
atlas_archive_first_difference <- function(seen, wanted) {
  n <- min(nchar(seen), nchar(wanted))
  a <- strsplit(substr(seen, 1L, n), "")[[1]]
  b <- strsplit(substr(wanted, 1L, n), "")[[1]]
  i <- which(a != b)
  i <- if (length(i)) i[[1]] else n + 1L
  sprintf("from character %d, Zenodo has '%s', the ledger '%s'", i,
          substr(seen, max(1L, i - 20L), i + 40L), substr(wanted, max(1L, i - 20L), i + 40L))
}

#' Why a waiting draft must not publish itself: every reason found, or none.
#' record is the draft as Zenodo answered for it.
atlas_archive_draft_problems <- function(z, ledger, entry, record) {
  problems <- character()
  recorded <- !is.null(entry$title) && !is.null(entry$description) && !is.null(entry$drafted_at) &&
    length(entry$files) && all(vapply(entry$files, function(f) !is.null(f$md5), logical(1)))
  if (!recorded) {
    return(paste("the ledger does not record what this draft was made with (title, description, MD5s and",
                 "when it was ready): it was made before drafts could publish themselves, so a person",
                 "checks it on zenodo.org and publishes it with archive-publish"))
  }
  if (!identical(as.character(record$id %||% ""), as.character(entry$deposition_id))) {
    problems <- c(problems, paste0("Zenodo answered for record ", record$id %||% "?", ", not ", entry$deposition_id))
  }
  metadata <- record$metadata %||% list()
  if (!identical(as.character(metadata$version %||% ""), entry$version)) {
    problems <- c(problems, paste0("its version label on Zenodo is '", metadata$version %||% "", "', not '", entry$version, "'"))
  }
  if (!identical(as.character(metadata$title %||% ""), entry$title)) {
    problems <- c(problems, paste0("its title on Zenodo is '", metadata$title %||% "", "', not the one it was made with"))
  }
  seen <- atlas_archive_reader_text(metadata$description)
  wanted <- atlas_archive_reader_text(entry$description)
  if (!identical(seen, wanted)) {
    problems <- c(problems, paste0("its description was changed on Zenodo since it was made (",
                                   atlas_archive_first_difference(seen, wanted), ")"))
  }

  latest <- atlas_archive_latest(ledger)
  if (!is.null(latest) && !is.null(ledger$concept_recid) &&
      !identical(as.character(record$conceptrecid %||% ""), as.character(ledger$concept_recid))) {
    problems <- c(problems, paste0("it is not a version of the series' record (concept ", record$conceptrecid %||% "none",
                                   ", the ledger's ", ledger$concept_recid, ")"))
  }

  listed <- z$call("GET", paste0("/deposit/depositions/", entry$deposition_id, "/files")) %||% list()
  names <- vapply(listed, function(f) as.character(f$filename %||% ""), character(1))
  wanted_names <- vapply(entry$files, function(f) f$name, character(1))
  if (any(duplicated(names))) problems <- c(problems, paste("Zenodo holds more than one", paste(unique(names[duplicated(names)]), collapse = ", ")))
  missing <- setdiff(wanted_names, names)
  extra <- setdiff(names, wanted_names)
  if (length(missing)) problems <- c(problems, paste("files missing on Zenodo:", paste(missing, collapse = ", ")))
  if (length(extra)) problems <- c(problems, paste("files on Zenodo the ledger does not list:", paste(extra, collapse = ", ")))
  for (f in entry$files) {
    there <- listed[names == f$name]
    if (length(there) != 1L) next
    md5 <- sub("^md5:", "", as.character(there[[1]]$checksum %||% ""))
    if (!identical(md5, f$md5)) problems <- c(problems, paste0(f$name, " has MD5 ", md5, " on Zenodo, not ", f$md5))
    size <- there[[1]]$filesize
    if (!is.null(size) && !isTRUE(all.equal(as.numeric(size), as.numeric(f$bytes)))) {
      problems <- c(problems, paste0(f$name, " is ", size, " bytes on Zenodo, not ", f$bytes))
    }
  }

  # Text a person put into the published version's description by hand may
  # belong in this one too, or may no longer be true of it. Only a person can
  # say which.
  if (!is.null(latest)) {
    if (is.null(latest$description)) {
      problems <- c(problems, paste0(
        "the ledger does not record the description the code wrote for the published version ", latest$version,
        ", so text a person added to it on zenodo.org (as the 76-records paragraph was) cannot be told apart: ",
        "a person reads both descriptions and publishes this draft with archive-publish"))
    } else {
      published <- z$call("GET", paste0("/deposit/depositions/", latest$deposition_id))
      live <- atlas_archive_reader_text(published$metadata$description)
      if (!identical(live, atlas_archive_reader_text(latest$description))) {
        problems <- c(problems, paste0(
          "the published version ", latest$version, "'s description on Zenodo has text the code did not write (",
          atlas_archive_first_difference(live, atlas_archive_reader_text(latest$description)), "): a person decides ",
          "whether it carries into this version, and publishes with archive-publish"))
      }
    }
  }
  problems
}

#' One series: what its waiting draft is now, acted on. Returns one row.
atlas_archive_auto_publish_series <- function(store, series, z, after_days, now) {
  row <- function(outcome, version = "", detail = "") {
    data.frame(series = series, version = version, outcome = outcome, detail = detail, stringsAsFactors = FALSE)
  }
  ledger <- atlas_archive_ledger(store, series)
  states <- vapply(ledger$versions, function(v) as.character(v$state %||% ""), character(1))
  drafts <- which(states == "draft")
  if (!length(drafts)) {
    uploading <- which(states == "uploading")
    if (length(uploading)) {
      v <- ledger$versions[[uploading[[1]]]]
      return(row("uploading", v$version,
                 "an upload stopped part way or is running; it is not a draft yet, so nothing publishes"))
    }
    return(row("nothing waiting"))
  }
  if (length(drafts) > 1L) {
    return(row("refused", "", paste("the ledger holds", length(drafts), "drafts; a person sorts them out")))
  }
  index <- drafts[[1]]
  entry <- ledger$versions[[index]]
  client <- z()
  path <- paste0("/deposit/depositions/", entry$deposition_id)
  answer <- client$call("GET", path, expect = c(200L, 404L, 410L), raw = TRUE)

  if (answer$status %in% c(404L, 410L)) {
    # Only gone if this token can still see the series' published record: a
    # token for another account would see nothing at all.
    latest <- atlas_archive_latest(ledger)
    if (!is.null(latest)) client$call("GET", paste0("/deposit/depositions/", latest$deposition_id))
    entry$state <- "discarded"
    entry$discarded_at <- atlas_archive_stamp(now)
    ledger$versions[[index]] <- entry
    atlas_archive_save_ledger(store, ledger)
    return(row("discarded", entry$version, paste("deleted on Zenodo; the ledger marks it discarded")))
  }

  record <- answer$body
  if (isTRUE(record$submitted)) {
    if (!nzchar(as.character(record$doi %||% ""))) {
      return(row("waiting", entry$version, "published on zenodo.org, but Zenodo gives no DOI yet; read again next run"))
    }
    entry$state <- "published"
    entry$doi <- record$doi
    entry$record_id <- record$record_id %||% record$id
    entry$url <- record$links$html %||% entry$url
    entry$published_at <- atlas_archive_stamp(now)
    entry$published_by <- "a person, on zenodo.org"
    ledger$versions[[index]] <- entry
    ledger$concept_doi <- record$conceptdoi %||% ledger$concept_doi
    ledger$concept_recid <- record$conceptrecid %||% ledger$concept_recid
    atlas_archive_save_ledger(store, ledger)
    return(row("published by hand", entry$version, paste0("doi:", record$doi)))
  }

  problems <- atlas_archive_draft_problems(client, ledger, entry, record)
  if (length(problems)) {
    return(row("refused", entry$version, paste0("not published: ", paste(problems, collapse = "; "), ". Draft: ", entry$url)))
  }
  ready <- atlas_archive_time(entry$drafted_at)
  due <- ready + after_days * 86400
  if (!is.finite(after_days) || now < due) {
    when <- if (is.finite(after_days)) paste("publishes itself after", atlas_archive_stamp(due)) else "publishing itself is off"
    return(row("waiting", entry$version, paste0("passes its checks; ", when,
                                                " unless deleted on zenodo.org: ", entry$url)))
  }
  ledger <- atlas_archive_publish(store, series, client, quiet = TRUE)
  done <- ledger$versions[[index]]
  row("published", entry$version, paste0("doi:", done$doi, " (all versions: doi:", ledger$concept_doi %||% "?", ")"))
}

#' Every series' waiting draft, for one target: deleted ones marked
#' discarded, hand-published ones recorded, and ones past the grace period
#' published if they read back as made. Safe to run as often as wanted.
#'
#' Sandbox ledgers (series ending -sandbox) are handled only with
#' target = "sandbox", against the sandbox. z is a Zenodo client, or a function
#' making one: it is only made when a draft is waiting, so a run with nothing
#' to do needs no token. Returns one row per series.
atlas_archive_auto_publish <- function(store, target = c("zenodo", "sandbox"),
                                       z = function() atlas_zenodo(target),
                                       after_days = atlas_archive_publish_after_days(),
                                       now = Sys.time(), quiet = FALSE) {
  target <- match.arg(target)
  keys <- store$list("archives/")
  series <- sub("^archives/(.*)[.]json$", "\\1", keys[grepl("^archives/[^/]+[.]json$", keys)])
  series <- sort(series[endsWith(series, "-sandbox") == identical(target, "sandbox")])
  client <- NULL
  connect <- function() {
    if (is.null(client)) {
      client <<- if (is.function(z)) z() else z
      if (!identical(client$target, target)) {
        stop("a ", client$target, " client cannot act on ", target, " ledgers", call. = FALSE)
      }
    }
    client
  }
  rows <- lapply(series, function(s) {
    tryCatch(
      atlas_archive_auto_publish_series(store, s, connect, after_days, now),
      error = function(e) {
        data.frame(series = s, version = "", outcome = "failed",
                   detail = paste("stopped:", conditionMessage(e)), stringsAsFactors = FALSE)
      }
    )
  })
  out <- if (length(rows)) do.call(rbind, rows) else
    data.frame(series = character(), version = character(), outcome = character(), detail = character())
  if (!isTRUE(quiet)) {
    if (!nrow(out)) message("no ", target, " archive series yet")
    for (i in seq_len(nrow(out))) {
      message(out$series[i], if (nzchar(out$version[i])) paste0(" version ", out$version[i]), ": ", out$outcome[i],
              if (nzchar(out$detail[i])) paste0(": ", out$detail[i]))
    }
  }
  invisible(out)
}
