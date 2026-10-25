# A pull's data QA report, with hard stops (the independent review,
# 2026-10-25; Steve approved the design and its first thresholds). The suites
# catch code bugs; this catches data ones: a bird in the taxa list, a
# bacterium naming a fungus, a source's records suddenly at town centres, a
# cache or grant that quietly failed.
#
# Every pull writes occurrences/qa-latest.json (and a dated copy): counts and
# shares only, never a record or place, each check beside the last pull's
# value. A check that crosses its threshold is a stop. A stopped pull is
# kept, but nothing is planned from it (atlas_qa_gate, called by the nightly
# and plan-job) unless that pull's stop is accepted by name:
#
#   ./atlas plan-job --accept-qa=<pull stamp>:<check>[,<check>...]
#
# and the acceptance is written into the job, so a release that went past a
# stop says so in its lineage.

ATLAS_QA_THRESHOLDS <- list(
  # Any modelled name whose kingdom is known and is not Fungi, unless allowed.
  kingdom_other = 0,
  # Records sharing one source:number key (the key rule, R/keys.R).
  duplicate_keys = 0,
  # MO records placed at a named place's centre: share of MO, and its rise.
  place_centre_share = 0.10, place_centre_rise = 0.02,
  # Records whose source answer is not cached: share, and its rise.
  uncached_share = 0.05, uncached_rise = 0.02,
  # Records left out because their sequences disagree: rise in share.
  disagree_rise = 0.01,
  # Drop-list rows still in the pull.
  drop_list = 0,
  # Records by source against the last pull.
  source_fall = 0.02, source_rise = 0.15,
  # The privacy list shrinking against the last pull.
  privacy_fall = 0.05
)
ATLAS_QA_FUNGI <- "Fungi"

atlas_qa_path <- function(stamp = NULL) {
  atlas_path("occurrences", if (is.null(stamp)) "qa-latest.json" else paste0("qa-", stamp, ".json"))
}
atlas_kingdoms_path <- function() atlas_path("occurrences", "kingdoms.tsv.gz")
atlas_kingdom_allow_path <- function() atlas_path("occurrences", "kingdom-allow.txt")

# New names a pull looks up, and the pause between lookups: GBIF's API is
# shared, so Atlas asks politely (ATLAS_QA_KINGDOM_CAP, ATLAS_QA_KINGDOM_PACE_MS
# override them; fill-kingdoms takes a larger cap once).
ATLAS_QA_KINGDOM_CAP <- 2000L
ATLAS_QA_KINGDOM_PACE_SECONDS <- 0.2

#' A name's kingdom from GBIF's backbone (species/match): "Fungi", another
#' kingdom, or NA when GBIF matches nothing or cannot be reached. Asked as
#' MycoMap Atlas, so GBIF can see who is calling; a "slow down" (429) waits
#' a minute and asks once more.
atlas_gbif_kingdom <- function(name, wait = Sys.sleep) {
  url <- paste0("https://api.gbif.org/v1/species/match?verbose=false&name=", utils::URLencode(name, reserved = TRUE))
  ask <- function() tryCatch({
    handle <- curl::new_handle(timeout = 20, useragent = "MycoMap Atlas (atlas.mycomap.org; info@mycomap.org)")
    curl::curl_fetch_memory(url, handle = handle)
  }, error = function(e) NULL)
  response <- ask()
  if (!is.null(response) && response$status_code == 429) {
    wait(60)
    response <- ask()
  }
  answer <- if (!is.null(response) && response$status_code == 200) {
    tryCatch(jsonlite::fromJSON(rawToChar(response$content)), error = function(e) NULL)
  }
  kingdom <- answer$kingdom
  if (is.character(kingdom) && length(kingdom) == 1L && nzchar(kingdom)) kingdom else NA_character_
}

#' The kingdom of each name: from the cache, looking up at most max_new names
#' it does not hold (the rest stay unchecked until a later pull), and
#' keeping what it learns. A name GBIF cannot place is kept as unknown and
#' asked again after a month.
atlas_name_kingdoms <- function(names, lookup = atlas_gbif_kingdom, max_new = ATLAS_QA_KINGDOM_CAP,
                                path = atlas_kingdoms_path(), today = Sys.Date(),
                                pace_seconds = 0, wait = Sys.sleep, save_every = 500L) {
  names <- sort(unique(as.character(names)))
  cache <- if (file.exists(path)) {
    utils::read.delim(gzfile(path, encoding = "UTF-8"), sep = "	", quote = "", comment.char = "", na.strings = "",
                      colClasses = "character", stringsAsFactors = FALSE)
  }
  if (is.null(cache) || !nrow(cache)) cache <- data.frame(name = character(), kingdom = character(), checked = character())
  unknown <- is.na(cache$kingdom) | !nzchar(cache$kingdom)
  stale <- unknown & as.Date(cache$checked) < as.Date(today) - 30
  known <- cache$name[!stale]
  ask <- utils::head(setdiff(names, known), max_new)
  if (length(ask)) {
    # Kept every save_every names, so a long fill that stops keeps what it
    # learned.
    keep <- function(names, found) {
      cache <<- rbind(cache[!cache$name %in% names, , drop = FALSE],
                      data.frame(name = names, kingdom = ifelse(is.na(found), "", found),
                                 checked = as.character(today), stringsAsFactors = FALSE))
      atlas_write_tsv_gz(cache, path)
    }
    found <- character(length(ask))
    done <- 0L
    for (i in seq_along(ask)) {
      if (i > 1L && pace_seconds > 0) wait(pace_seconds)
      found[[i]] <- lookup(ask[[i]]) %||% NA_character_
      if (i - done >= save_every) {
        keep(ask[(done + 1L):i], found[(done + 1L):i])
        done <- i
      }
    }
    if (done < length(ask)) keep(ask[(done + 1L):length(ask)], found[(done + 1L):length(ask)])
  }
  kingdom <- cache$kingdom[match(names, cache$name)]
  stats::setNames(ifelse(is.na(kingdom) | !nzchar(kingdom), NA_character_, kingdom), names)
}

#' Fill the kingdom cache for a pull's names once, at a larger cap than a
#' pull's (Steve, 2026-10-25: every name checked before the first nightly).
#' pull is a pull file, or NULL for this machine's latest; the cache is this
#' machine's (atlas_kingdoms_path), where the nightly's QA reads it.
atlas_fill_kingdoms <- function(pull = NULL, cap = 20000L, pace_seconds = ATLAS_QA_KINGDOM_PACE_SECONDS,
                                lookup = atlas_gbif_kingdom, wait = Sys.sleep, quiet = FALSE) {
  occurrences <- atlas_read_occurrences(pull)
  names <- unique(as.character(occurrences$scientific_name))
  kingdoms <- atlas_name_kingdoms(names, lookup = lookup, max_new = cap, pace_seconds = pace_seconds, wait = wait)
  counts <- list(names = length(names), fungi = sum(kingdoms %in% ATLAS_QA_FUNGI),
                 other = sum(!is.na(kingdoms) & kingdoms != ATLAS_QA_FUNGI), unknown = sum(is.na(kingdoms)),
                 cache = atlas_kingdoms_path())
  if (!isTRUE(quiet)) {
    message(sprintf("kingdoms: %d names, %d fungi, %d other, %d unknown -> %s", counts$names, counts$fungi,
                    counts$other, counts$unknown, counts$cache))
  }
  invisible(counts)
}

#' One check: its value, the last pull's, whether it stops, and why.
atlas_qa_check <- function(value, previous = NULL, stop = FALSE, why = NULL, detail = NULL) {
  Filter(Negate(is.null), list(value = value, previous = previous, stop = isTRUE(stop),
                               why = if (isTRUE(stop)) why, detail = detail))
}

#' The QA report of a pull. occurrences is the pull as written; manifest its
#' latest.json; audit its labels audit (R/labels.R); privacy its privacy list
#' (source, observation_id, privacy); previous the last pull's report or NULL;
#' kingdoms the kingdom of each modelled name (atlas_name_kingdoms); allow
#' the names allowed another kingdom. Pure.
atlas_qa_report <- function(occurrences, manifest, audit = NULL, privacy = NULL, previous = NULL,
                            kingdoms = NULL, allow = character(), exclusions = NULL,
                            thresholds = ATLAS_QA_THRESHOLDS) {
  t <- thresholds
  last <- function(name) previous$checks[[name]]$value
  share <- function(k, n) if (n) k / n else 0
  checks <- list()

  # Kingdom of every modelled name.
  names <- sort(unique(as.character(occurrences$scientific_name)))
  if (!is.null(kingdoms)) {
    k <- kingdoms[names]
    other <- names[!is.na(k) & k != ATLAS_QA_FUNGI & !names %in% allow]
    checks$kingdom <- atlas_qa_check(
      length(other), last("kingdom"), stop = length(other) > t$kingdom_other,
      why = paste0(length(other), " modelled names are not fungi: ", paste(utils::head(other, 10), collapse = ", ")),
      detail = list(names = length(names), checked = sum(!is.na(k)), unknown = sum(is.na(k)),
                    other = as.list(utils::head(other, 50)))
    )
  }

  # The key rule on live data: no two records share a source:number key.
  keys <- atlas_record_key(occurrences$source, occurrences$observation_id)
  duplicated_keys <- sum(duplicated(keys))
  shared <- sum(vapply(split(occurrences$source, occurrences$observation_id), function(s) length(unique(s)) > 1L, TRUE))
  checks$keys <- atlas_qa_check(duplicated_keys, last("keys"), stop = duplicated_keys > t$duplicate_keys,
                                why = paste0(duplicated_keys, " records share a source:number key"),
                                detail = list(numbers_shared_across_sources = shared))

  # MO records at a named place's centre, and records with no cached answer.
  by_source <- table(as.character(occurrences$source))
  mo <- as.integer(by_source[ATLAS_MO_SOURCE] %||% 0L)
  mo[is.na(mo)] <- 0L
  if (!is.null(privacy) && nrow(privacy)) {
    in_pull <- atlas_record_key(privacy$source, privacy$observation_id) %in% keys
    p <- privacy[in_pull, , drop = FALSE]
    centre <- sum(p$source == ATLAS_MO_SOURCE & p$privacy == "place")
    unknown <- sum(p$privacy == "unknown")
    checks$place_centres <- atlas_qa_check(
      share(centre, mo), last("place_centres"),
      stop = share(centre, mo) > t$place_centre_share ||
        (!is.null(last("place_centres")) && share(centre, mo) - last("place_centres") > t$place_centre_rise),
      why = sprintf("%.1f%% of MO records are placed at a named place's centre", 100 * share(centre, mo)),
      detail = list(records = centre, of = mo)
    )
    checks$uncached <- atlas_qa_check(
      share(unknown, nrow(occurrences)), last("uncached"),
      stop = share(unknown, nrow(occurrences)) > t$uncached_share ||
        (!is.null(last("uncached")) && share(unknown, nrow(occurrences)) - last("uncached") > t$uncached_rise),
      why = sprintf("%.1f%% of records have no cached source answer", 100 * share(unknown, nrow(occurrences))),
      detail = list(records = unknown)
    )
    previous_size <- previous$detail$privacy_list
    checks$privacy_list <- atlas_qa_check(
      nrow(privacy), previous_size,
      stop = !is.null(previous_size) && previous_size > 0 && (previous_size - nrow(privacy)) / previous_size > t$privacy_fall,
      why = sprintf("the privacy list shrank from %d to %d entries", as.integer(previous_size %||% 0L), nrow(privacy))
    )
  }

  # Naming: the share left out because their sequences disagree.
  if (!is.null(audit$by_status)) {
    status <- stats::setNames(as.integer(audit$by_status$records), audit$by_status$status)
    pulled <- as.integer(audit$pulled %||% sum(status))
    disagree <- share(sum(status[grepl("disagree", names(status))]), pulled)
    checks$naming <- atlas_qa_check(
      disagree, last("naming"),
      stop = !is.null(last("naming")) && disagree - last("naming") > t$disagree_rise,
      why = sprintf("records with disagreeing sequence names rose to %.1f%%", 100 * disagree),
      detail = list(by_status = as.list(status))
    )
  }

  # The drop list: none of its rows may be in the pull.
  if (!is.null(exclusions) && length(exclusions)) {
    present <- sum(as.character(occurrences$id) %in% exclusions | keys %in% exclusions)
    checks$drop_list <- atlas_qa_check(present, last("drop_list"), stop = present > t$drop_list,
                                       why = paste0(present, " drop-list rows are in the pull"))
  }

  # Records by source against the last pull.
  now <- as.list(stats::setNames(as.integer(by_source), names(by_source)))
  before <- previous$detail$by_source
  moved <- character()
  if (!is.null(before)) {
    for (s in union(names(now), names(before))) {
      a <- as.numeric(before[[s]] %||% 0)
      b <- as.numeric(now[[s]] %||% 0)
      if (a > 0 && ((a - b) / a > t$source_fall || (b - a) / a > t$source_rise)) {
        moved <- c(moved, sprintf("%s %d -> %d", s, as.integer(a), as.integer(b)))
      }
    }
  }
  checks$sources <- atlas_qa_check(length(moved), NULL, stop = length(moved) > 0L,
                                   why = paste("records by source moved past their limits:", paste(moved, collapse = "; ")))

  stops <- names(checks)[vapply(checks, function(c) isTRUE(c$stop), TRUE)]
  list(
    pull = manifest$stamp %||% NA_character_, records = nrow(occurrences), taxa = length(names),
    checks = checks, stops = as.list(stops), thresholds = thresholds,
    not_measured = list(twins = "cross-post pairs more than 5 km apart: needs the twin lists",
                        deleted_at_source = "deleted MO records on the privacy list: the pull does not carry the marker"),
    detail = list(by_source = now, privacy_list = if (!is.null(privacy)) nrow(privacy))
  )
}

#' Make and write this pull's QA report beside it: qa-<stamp>.json and
#' qa-latest.json, the last report read first as the one to compare with.
atlas_pull_qa <- function(occurrences, manifest, audit = NULL, kingdoms = NULL, quiet = FALSE) {
  previous <- if (file.exists(atlas_qa_path())) jsonlite::fromJSON(atlas_qa_path(), simplifyVector = TRUE)
  privacy <- if (file.exists(atlas_privacy_path())) {
    utils::read.delim(gzfile(atlas_privacy_path(), encoding = "UTF-8"), sep = "	", quote = "", comment.char = "",
                      na.strings = "", colClasses = "character", stringsAsFactors = FALSE)
  }
  allow <- if (file.exists(atlas_kingdom_allow_path())) trimws(readLines(atlas_kingdom_allow_path(), warn = FALSE))
  exclusions <- tryCatch(atlas_exclusion_keys(), error = function(e) NULL)
  report <- atlas_qa_report(occurrences, manifest, audit, privacy, previous, kingdoms = kingdoms,
                            allow = allow %||% character(), exclusions = exclusions)
  atlas_write_json(report, atlas_qa_path(manifest$stamp))
  atlas_write_json(report, atlas_qa_path())
  if (!isTRUE(quiet)) {
    message("pull QA: ", if (length(report$stops)) paste("STOP on", paste(unlist(report$stops), collapse = ", ")) else
      "no stop", " -> ", atlas_qa_path(manifest$stamp))
  }
  invisible(report)
}

#' The ids and keys on the drop list, or NULL when there is none.
atlas_exclusion_keys <- function() {
  rows <- atlas_read_exclusions()
  if (is.null(rows) || !nrow(rows)) return(NULL)
  # A row names a record by its .org id, or by source:number (R/exclude.R).
  unique(as.character(rows$id))
}

#' Refuse to plan from a pull whose QA report stops, unless each stop is
#' accepted by name for that pull (accept: "<stamp>:<check>[,<check>]").
#' Returns the accepted stops, to be written into the job. A pull with no
#' report (one made before this gate) is planned as before, and says so.
atlas_qa_gate <- function(accept = NULL, report = NULL, quiet = FALSE) {
  report <- report %||% if (file.exists(atlas_qa_path())) jsonlite::fromJSON(atlas_qa_path(), simplifyVector = TRUE)
  manifest <- atlas_read_manifest()
  if (is.null(report) || !identical(as.character(report$pull), as.character(manifest$stamp %||% ""))) {
    if (!isTRUE(quiet)) message("pull QA: no report for this pull; planning as before")
    return(invisible(list()))
  }
  stops <- as.character(unlist(report$stops))
  if (!length(stops)) return(invisible(list()))
  accepted <- character()
  if (!is.null(accept)) {
    parts <- strsplit(as.character(accept), ":", fixed = TRUE)[[1]]
    if (length(parts) == 2L && identical(parts[[1]], as.character(report$pull))) {
      accepted <- trimws(strsplit(parts[[2]], ",", fixed = TRUE)[[1]])
    }
  }
  left <- setdiff(stops, accepted)
  if (length(left)) {
    why <- vapply(left, function(s) as.character(report$checks[[s]]$why %||% s), "")
    stop("pull ", report$pull, " stopped its QA: ", paste(why, collapse = "; "),
         ". Nothing is planned; to plan anyway, accept by name: --accept-qa=", report$pull, ":",
         paste(left, collapse = ","), call. = FALSE)
  }
  invisible(list(pull = report$pull, accepted = as.list(intersect(stops, accepted))))
}
