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
#
# Plant specimens from the pool runs leave the pull by themselves (Steve,
# 2026-11-05): a name GBIF matches exactly, at species rank, in another kingdom
# is left out before the pull is fingerprinted or written, and named in its
# report, its manifest and the box's login banner, so a new one does not stop
# the night. The allow list wins over it. Anything less sure still stops the
# night under the kingdom check: Melanocarpum sp. 'PR01', a fungus GBIF answers
# only by a plant genus, is why a code never leaves this way.

ATLAS_QA_THRESHOLDS <- list(
  # Any modelled name whose kingdom is known and is not Fungi, unless allowed.
  kingdom_other = 0,
  # Records left out as exactly another kingdom, and any one name's. These stop
  # a fault that reads fungi as plants; the rows are left out either way. The
  # 2026-11-04 dry pull held 7 such records of 6 names, at most 2 a name, and no
  # fungus among its 16,233 names read this way. Approved sequences hold 92
  # observations, at most 4 a name, under all 78 such names in the pool runs on
  # 2026-11-05, validated or not. In the frozen pull, 2,880 names (74% of records)
  # hold over 10 records, so one of those misread stops the night by itself.
  left_out_records = 300, left_out_name_records = 10,
  # Records sharing one source:number key (the key rule, R/keys.R).
  duplicate_keys = 0,
  # MO records placed at a named place's centre: share of MO, and its rise.
  # The rise is what catches a source suddenly at centres; the ceiling is a
  # backstop for a first report or after a gap, and a ceiling stop does not
  # clear itself, so it sits above normal. It rests on two pulls only:
  # 38.5% (1,936 of 5,035, the frozen pull x73b85b36; 45.7% of its records
  # with a cached MO answer) and 41.0% (2,115 of 5,157, the dry pull of
  # 2026-11-04). By first validation and today's classes, the share read 49.9%
  # at the end of March 2026 and has fallen since, and one day in 181 moved it
  # more than 2 points. The first limit, 10%, was never measured against this
  # count (Steve, 2026-11-04).
  place_centre_share = 0.50, place_centre_rise = 0.02,
  # Records whose source answer is not cached: share, and its rise.
  uncached_share = 0.05, uncached_rise = 0.02,
  # Records left out because their sequences disagree: rise in share.
  disagree_rise = 0.01,
  # Drop-list rows still in the pull.
  drop_list = 0,
  # Records by source against the last pull. Neither stops on fewer records
  # than source_floor (Steve, 2026-11-04): with 43 Sequences records one is
  # 2.3%, and with 2 GenBank records one is 50%, while a failed cache or grant
  # moves far more. Smaller moves past a limit stay in the report.
  source_fall = 0.02, source_rise = 0.15, source_floor = 20,
  # The privacy list shrinking against the last pull.
  privacy_fall = 0.05,
  # The newest first validation in the pull, in days before the pull: .org's
  # validated records come through the .com mirror, so a mirror that stops
  # refreshing (as on 2026-10-25) shows as no new first-green dates. From
  # 2026-05-01 to 2026-10-26 there was a validation on every one of 179 days
  # (no gap over 1 day), so 3 days leaves a quiet weekend's room.
  newest_green_days = 3
)
ATLAS_QA_FUNGI <- "Fungi"
# The Atlas covers fungi and slime moulds (Steve, 2026-11-04). GBIF files slime
# moulds as the phylum Mycetozoa, so a new one needs no allow-list entry.
ATLAS_QA_SLIME_MOULDS <- "Mycetozoa"
# What a cached answer was asked with. An answer from an earlier way of asking
# is asked again (2: the name's match type is read, atlas_gbif_kingdom; 3: and
# kept, so an exact match to another kingdom can leave the pull).
ATLAS_QA_KINGDOM_LOOKUP_VERSION <- "3"
# How an answer that may leave the pull is marked, on the lookup's answer and in
# the cache's match column.
ATLAS_QA_MATCH_EXACT <- "exact"
ATLAS_QA_LEFT_OUT_RULE <- "GBIF matches the name exactly, at species rank, in another kingdom, and no fungus has that name"

atlas_qa_path <- function(stamp = NULL) {
  atlas_path("occurrences", if (is.null(stamp)) "qa-latest.json" else paste0("qa-", stamp, ".json"))
}
atlas_kingdoms_path <- function() atlas_path("occurrences", "kingdoms.tsv.gz")
atlas_kingdom_allow_path <- function() atlas_path("occurrences", "kingdom-allow.txt")
atlas_left_out_notice_path <- function() atlas_path("health", "pull-left-out.json", create = TRUE)

#' The names allowed another kingdom, read when a pull is made: no deploy needed.
atlas_kingdom_allow <- function(path = atlas_kingdom_allow_path()) {
  if (file.exists(path)) trimws(readLines(path, warn = FALSE)) else character()
}

# New names a pull looks up, and the pause between lookups: GBIF's API is
# shared, so Atlas asks politely (ATLAS_QA_KINGDOM_CAP, ATLAS_QA_KINGDOM_PACE_MS
# override them; fill-kingdoms takes a larger cap once).
ATLAS_QA_KINGDOM_CAP <- 2000L
ATLAS_QA_KINGDOM_PACE_SECONDS <- 0.2

#' One question to GBIF's backbone (species/match), or NULL when it cannot be
#' answered. Asked as MycoMap Atlas, so GBIF can see who is calling; a "slow
#' down" (429) waits a minute and asks once more.
atlas_gbif_query <- function(query, wait = Sys.sleep) {
  url <- paste0("https://api.gbif.org/v1/species/match?",
                paste(names(query), vapply(query, utils::URLencode, "", reserved = TRUE), sep = "=", collapse = "&"))
  ask <- function() tryCatch({
    handle <- curl::new_handle(timeout = 20, useragent = "MycoMap Atlas (atlas.mycomap.org; info@mycomap.org)")
    curl::curl_fetch_memory(url, handle = handle)
  }, error = function(e) NULL)
  response <- ask()
  if (!is.null(response) && response$status_code == 429) {
    wait(60)
    response <- ask()
  }
  if (is.null(response) || response$status_code != 200) return(NULL)
  tryCatch(jsonlite::fromJSON(rawToChar(response$content)), error = function(e) NULL)
}

#' What an answer's kingdom and phylum make a name: its kingdom, or the group
#' Atlas covers beside fungi (ATLAS_QA_SLIME_MOULDS), which GBIF files as a
#' phylum of Protozoa. NA when the answer holds no kingdom, or GBIF's own word
#' for none ("incertae sedis").
atlas_gbif_group <- function(answer) {
  kingdom <- answer$kingdom
  if (!is.character(kingdom) || length(kingdom) != 1L || is.na(kingdom) || !nzchar(kingdom)) return(NA_character_)
  if (identical(tolower(kingdom), "incertae sedis")) return(NA_character_)
  if (identical(answer$phylum, ATLAS_QA_SLIME_MOULDS)) ATLAS_QA_SLIME_MOULDS else kingdom
}

#' Is GBIF's answer this very species? EXACT alone is not enough: "Conocybe sect.
#' Candidae" read exactly as the family Candidae, "Subgenus Lentoramaria" as a
#' genus called Subgenus, and "picipes sp. 'BC02'" as an unranked beetle, each a
#' fungus (2026-11-05, the 49 names first read as not fungi).
atlas_gbif_this_species <- function(answer, name) {
  if (!identical(answer$matchType, "EXACT") || !isTRUE(answer$rank %in% c("SPECIES", "SUBSPECIES", "VARIETY", "FORM"))) return(FALSE)
  words <- function(x) utils::head(strsplit(tolower(trimws(as.character(x))), " +")[[1]], 2L)
  identical(words(answer$canonicalName %||% ""), words(name))
}

#' What an exact match to another kingdom makes a name. It may leave the pull
#' (marked ATLAS_QA_MATCH_EXACT) only when it is this very species and GBIF, asked
#' for a fungus of that name, has none: one with a fungus's name too reads as
#' fungi. A question unanswered leaves it unmarked, so it stops the night rather
#' than leaving unseen.
atlas_gbif_exact_other <- function(answer, name, wait, pace_seconds) {
  group <- atlas_gbif_group(answer)
  if (!atlas_gbif_this_species(answer, name)) return(group)
  wait(pace_seconds)
  fungus <- atlas_gbif_query(list(name = name, kingdom = ATLAS_QA_FUNGI, strict = "true"), wait = wait)
  if (is.null(fungus)) return(group)
  if (identical(fungus$kingdom, ATLAS_QA_FUNGI) && atlas_gbif_this_species(fungus, name)) return(ATLAS_QA_FUNGI)
  structure(group, match = ATLAS_QA_MATCH_EXACT)
}

#' A name's kingdom from GBIF's backbone, NA when GBIF cannot place it. GBIF
#' always answers with something, so the answer is only believed when it is
#' about this name (2026-11-04: of 49 names first read as not fungi, 8 were real
#' fungi, such as Hydnum atlanticum, fuzzily matched to the moss Hypnum):
#'   1. The name itself, believed for an exact match, or for a match at a higher
#'      rank below kingdom (a code such as Russula sp. 'IN1' answers for Russula).
#'      A section's name is not asked: its epithet matches whatever shares it.
#'   2. Its genus with a hint of Fungi. A genus several kingdoms share has no
#'      match without a hint (Mycena, Lactarius, most of 1,404 unplaced names).
#'      The hint decides between them but does not force an answer: a genus only
#'      in Protozoa still answers Protozoa.
#'   3. GBIF's alternatives for exactly that genus: fungi if any are fungi (Boletus
#'      has several, so no single match), else the one kingdom they agree on.
#'   4. With nothing else known of the genus, a fuzzy match to a species stands, as
#'      the only evidence there is: a misspelt bee (Protandrena labrosa) is better
#'      flagged than passed, and the allow list answers a false alarm.
#' A shared genus therefore reads as fungi, so a code in it can pass unseen; a
#' binomial is settled at step 1 first. Any question unanswered gives NA, never a
#' guess from the rest. An answer that may leave the pull says so in its match
#' attribute (atlas_gbif_exact_other).
atlas_gbif_kingdom <- function(name, wait = Sys.sleep, pace_seconds = ATLAS_QA_KINGDOM_PACE_SECONDS) {
  name <- trimws(as.character(name))
  name <- paste0(toupper(substr(name, 1, 1)), substr(name, 2, nchar(name)))
  genus <- sub(" .*$", "", name)
  if (genus %in% c("Subgenus", "Section")) return(NA_character_)
  fuzzy <- NA_character_
  if (!grepl(" (sect|subsect|subgen|ser)[.] ", name)) {
    plain <- atlas_gbif_query(list(verbose = "false", name = name), wait = wait)
    if (is.null(plain)) return(NA_character_)
    exact <- identical(plain$matchType, "EXACT") && !identical(plain$rank, "UNRANKED")
    above <- identical(plain$matchType, "HIGHERRANK") && !identical(plain$rank, "KINGDOM")
    group <- atlas_gbif_group(plain)
    if (exact && !is.na(group) && !group %in% c(ATLAS_QA_FUNGI, ATLAS_QA_SLIME_MOULDS)) {
      return(atlas_gbif_exact_other(plain, name, wait, pace_seconds))
    }
    if (exact || above) return(group)
    if (identical(plain$matchType, "FUZZY") && identical(plain$rank, "SPECIES")) fuzzy <- atlas_gbif_group(plain)
    wait(pace_seconds)
  }
  hinted <- atlas_gbif_query(list(name = genus, rank = "GENUS", kingdom = ATLAS_QA_FUNGI, strict = "true"), wait = wait)
  if (is.null(hinted)) return(NA_character_)
  if (identical(hinted$matchType, "EXACT")) return(atlas_gbif_group(hinted))
  wait(pace_seconds)
  full <- atlas_gbif_query(list(verbose = "true", name = genus), wait = wait)
  if (is.null(full)) return(NA_character_)
  others <- full$alternatives
  if (!is.data.frame(others) || !nrow(others) || is.null(others$canonicalName) || is.null(others$rank)) return(fuzzy)
  same <- others[others$rank %in% "GENUS" & others$canonicalName %in% genus, , drop = FALSE]
  groups <- unique(vapply(seq_len(nrow(same)), function(i) atlas_gbif_group(as.list(same[i, , drop = FALSE])), ""))
  groups <- groups[!is.na(groups)]
  if (ATLAS_QA_FUNGI %in% groups) return(ATLAS_QA_FUNGI)
  if (length(groups) == 1L) groups else fuzzy
}

#' The kingdom of each name: from the cache, looking up at most max_new names
#' it does not hold (the rest stay unchecked until a later pull), and
#' keeping what it learns. A name GBIF cannot place is kept as unknown and
#' asked again after a month. Its "exact" attribute names those whose answer, made
#' the current way, may leave the pull; an older answer stands but never does.
atlas_name_kingdoms <- function(names, lookup = atlas_gbif_kingdom, max_new = ATLAS_QA_KINGDOM_CAP,
                                path = atlas_kingdoms_path(), today = Sys.Date(),
                                pace_seconds = 0, wait = Sys.sleep, save_every = 500L) {
  names <- sort(unique(as.character(names)))
  cache <- if (file.exists(path)) {
    utils::read.delim(gzfile(path, encoding = "UTF-8"), sep = "	", quote = "", comment.char = "", na.strings = "",
                      colClasses = "character", stringsAsFactors = FALSE)
  }
  if (is.null(cache) || !nrow(cache)) {
    cache <- data.frame(name = character(), kingdom = character(), checked = character(), lookup = character(),
                        match = character())
  }
  if (is.null(cache$lookup)) cache$lookup <- rep("", nrow(cache))
  if (is.null(cache$match)) cache$match <- rep("", nrow(cache))
  unknown <- is.na(cache$kingdom) | !nzchar(cache$kingdom)
  stale <- (unknown & as.Date(cache$checked) < as.Date(today) - 30) | !cache$lookup %in% ATLAS_QA_KINGDOM_LOOKUP_VERSION
  known <- cache$name[!stale]
  ask <- utils::head(setdiff(names, known), max_new)
  if (length(ask)) {
    # Kept every save_every names, so a long fill that stops keeps what it
    # learned.
    keep <- function(names, found, how) {
      cache <<- rbind(cache[!cache$name %in% names, , drop = FALSE],
                      data.frame(name = names, kingdom = ifelse(is.na(found), "", found),
                                 checked = as.character(today), lookup = ATLAS_QA_KINGDOM_LOOKUP_VERSION,
                                 match = how, stringsAsFactors = FALSE))
      atlas_write_tsv_gz(cache, path)
    }
    found <- character(length(ask))
    how <- character(length(ask))
    done <- 0L
    for (i in seq_along(ask)) {
      if (i > 1L && pace_seconds > 0) wait(pace_seconds)
      answer <- lookup(ask[[i]]) %||% NA_character_
      found[[i]] <- answer
      how[[i]] <- attr(answer, "match", exact = TRUE) %||% ""
      if (i - done >= save_every) {
        keep(ask[(done + 1L):i], found[(done + 1L):i], how[(done + 1L):i])
        done <- i
      }
    }
    if (done < length(ask)) keep(ask[(done + 1L):length(ask)], found[(done + 1L):length(ask)], how[(done + 1L):length(ask)])
  }
  row <- match(names, cache$name)
  kingdom <- cache$kingdom[row]
  out <- stats::setNames(ifelse(is.na(kingdom) | !nzchar(kingdom), NA_character_, kingdom), names)
  exact <- names[cache$match[row] %in% ATLAS_QA_MATCH_EXACT & cache$lookup[row] %in% ATLAS_QA_KINGDOM_LOOKUP_VERSION]
  if (length(exact)) attr(out, "exact") <- exact
  out
}

#' The kingdoms a pull reads: GBIF is asked for new names only where
#' ATLAS_QA_KINGDOM_LOOKUP=gbif (the box); elsewhere the cache alone answers.
atlas_pull_kingdoms <- function(names) {
  gbif <- identical(Sys.getenv("ATLAS_QA_KINGDOM_LOOKUP"), "gbif")
  number <- function(name, unset) {
    value <- suppressWarnings(as.numeric(Sys.getenv(name, unset = "")))
    if (length(value) == 1L && is.finite(value) && value >= 0) value else unset
  }
  atlas_name_kingdoms(
    names, lookup = if (gbif) atlas_gbif_kingdom else function(name) NA_character_,
    max_new = if (gbif) as.integer(number("ATLAS_QA_KINGDOM_CAP", ATLAS_QA_KINGDOM_CAP)) else 0L,
    pace_seconds = number("ATLAS_QA_KINGDOM_PACE_MS", 1000 * ATLAS_QA_KINGDOM_PACE_SECONDS) / 1000
  )
}

#' Leave out the records of names GBIF matches exactly in another kingdom
#' (atlas_name_kingdoms' "exact"), unless allowed: the rows kept, and what the
#' pull's manifest and report say about it. Slime moulds, unknown names, and an
#' answer less sure than that all stay. Pure.
atlas_kingdom_left_out <- function(occurrences, kingdoms = NULL, allow = character()) {
  name <- as.character(occurrences$scientific_name)
  covered <- c(ATLAS_QA_FUNGI, ATLAS_QA_SLIME_MOULDS)
  found <- if (is.null(kingdoms)) rep(NA_character_, length(name)) else as.character(kingdoms[name])
  drop <- name %in% attr(kingdoms, "exact") & !is.na(found) & !found %in% covered & !name %in% allow
  left <- sort(unique(name[drop]))
  rows <- data.frame(name = left, kingdom = found[match(left, name)],
                     records = as.integer(table(factor(name[drop], levels = left))), stringsAsFactors = FALSE)
  kept <- occurrences[!drop, , drop = FALSE]
  rownames(kept) <- NULL
  list(kept = kept, info = list(rule = ATLAS_QA_LEFT_OUT_RULE, records = sum(drop), names = rows))
}

#' Say which names newly left the pull, in the box's health directory, where the
#' login banner reads it (deploy/lightsail/alert.sh): the box has no mailer. The
#' note gathers names until someone reads it and clears it with
#' alert.sh --ok pull-left-out. Pulls that leave out no new name do not touch it.
atlas_note_left_out <- function(rows, new, now = Sys.time(), shown = 20L) {
  if (!length(new)) return(invisible(NULL))
  path <- atlas_left_out_notice_path()
  stamp <- format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  old <- if (file.exists(path)) tryCatch(jsonlite::fromJSON(path), error = function(e) NULL)
  noted <- identical(old$state, "notice")
  fresh <- rows[rows$name %in% new, , drop = FALSE]
  held <- unique(c(if (noted) as.character(old$names), sprintf("%s (%s, %d)", fresh$name, fresh$kingdom, fresh$records)))
  more <- length(held) - shown
  text <- sprintf(
    "%d names left the pull as not fungi: %s%s. If one is a fungus, add it to occurrences/kingdom-allow.txt. Clear: alert.sh --ok pull-left-out",
    length(held), paste(utils::head(held, shown), collapse = ", "), if (more > 0L) sprintf(", and %d more (qa-latest.json)", more) else ""
  )
  # One line, message last: alert.sh reads the file with sed.
  note <- jsonlite::toJSON(list(check = "pull-left-out", state = "notice", since = if (noted) old$since else stamp,
                                checked = stamp, names = as.list(held), message = text), auto_unbox = TRUE)
  writeBin(charToRaw(paste0(note, "\n")), path)
  invisible(path)
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
  covered <- c(ATLAS_QA_FUNGI, ATLAS_QA_SLIME_MOULDS)
  counts <- list(names = length(names), fungi = sum(kingdoms %in% ATLAS_QA_FUNGI),
                 slime_moulds = sum(kingdoms %in% ATLAS_QA_SLIME_MOULDS),
                 other = sum(!is.na(kingdoms) & !kingdoms %in% covered),
                 exact_other = sum(names(kingdoms) %in% attr(kingdoms, "exact") & !kingdoms %in% covered),
                 unknown = sum(is.na(kingdoms)),
                 cache = atlas_kingdoms_path())
  if (!isTRUE(quiet)) {
    message(sprintf("kingdoms: %d names, %d fungi, %d slime moulds, %d other (%d exact, which leave the pull unless allowed), %d unknown -> %s",
                    counts$names, counts$fungi, counts$slime_moulds, counts$other, counts$exact_other, counts$unknown, counts$cache))
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
#' the names allowed another kingdom; left_out what atlas_kingdom_left_out took
#' from this pull. Pure.
atlas_qa_report <- function(occurrences, manifest, audit = NULL, privacy = NULL, previous = NULL,
                            kingdoms = NULL, allow = character(), exclusions = NULL, left_out = NULL,
                            thresholds = ATLAS_QA_THRESHOLDS) {
  t <- thresholds
  last <- function(name) previous$checks[[name]]$value
  share <- function(k, n) if (n) k / n else 0
  checks <- list()

  # Kingdom of every modelled name.
  names <- sort(unique(as.character(occurrences$scientific_name)))
  if (!is.null(kingdoms)) {
    k <- kingdoms[names]
    other <- names[!is.na(k) & !k %in% c(ATLAS_QA_FUNGI, ATLAS_QA_SLIME_MOULDS) & !names %in% allow]
    checks$kingdom <- atlas_qa_check(
      length(other), last("kingdom"), stop = length(other) > t$kingdom_other,
      why = paste0(length(other), " modelled names are neither fungi nor slime moulds: ", paste(utils::head(other, 10), collapse = ", ")),
      detail = list(names = length(names), checked = sum(!is.na(k)), unknown = sum(is.na(k)),
                    slime_moulds = sum(k %in% ATLAS_QA_SLIME_MOULDS),
                    other = as.list(utils::head(other, 50)))
    )
  }

  # What left the pull as exactly another kingdom: by name, each one new since
  # the last pull marked, and a stop if the count looks like a fault.
  if (!is.null(left_out)) {
    rows <- left_out$names
    before <- as.character(previous$checks$kingdom_left_out$detail$left_out$name)
    large <- rows$name[rows$records > t$left_out_name_records]
    too_many <- left_out$records > t$left_out_records
    checks$kingdom_left_out <- atlas_qa_check(
      left_out$records, last("kingdom_left_out"), stop = too_many || length(large) > 0L,
      why = paste0(left_out$records, " records of ", nrow(rows), " names left the pull as not fungi",
                   if (length(large)) paste0("; each with over ", t$left_out_name_records, " records: ", paste(utils::head(large, 10), collapse = ", ")),
                   "; is the kingdom lookup at fault?"),
      detail = list(rule = left_out$rule, names = nrow(rows), new = as.list(setdiff(rows$name, before)), left_out = rows)
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

  # A stale mirror: the newest first validation the pull holds, against the
  # day it was pulled.
  pulled <- as.Date(substr(as.character(manifest$pulled_at %||% NA_character_), 1, 10))
  green <- occurrences[[ATLAS_FIRST_GREEN_FIELD]]
  green <- if (is.null(green)) character() else as.character(green[!is.na(green) & nzchar(green)])
  if (!is.na(pulled) && length(green)) {
    newest <- max(as.Date(substr(green, 1, 10)), na.rm = TRUE)
    age <- as.integer(pulled - newest)
    checks$newest_green <- atlas_qa_check(
      age, last("newest_green"), stop = age > t$newest_green_days,
      why = sprintf("the newest first validation in the pull is %d days old (%s); is the .com mirror refreshing?",
                    age, format(newest)),
      detail = list(newest = format(newest), pulled = format(pulled))
    )
  }

  # Records by source against the last pull.
  now <- as.list(stats::setNames(as.integer(by_source), names(by_source)))
  before <- previous$detail$by_source
  moved <- character()
  below_floor <- character()
  if (!is.null(before)) {
    for (s in union(names(now), names(before))) {
      a <- as.numeric(before[[s]] %||% 0)
      b <- as.numeric(now[[s]] %||% 0)
      if (a > 0 && ((a - b) / a > t$source_fall || (b - a) / a > t$source_rise)) {
        change <- sprintf("%s %d -> %d", s, as.integer(a), as.integer(b))
        if (abs(b - a) >= t$source_floor) moved <- c(moved, change) else below_floor <- c(below_floor, change)
      }
    }
  }
  checks$sources <- atlas_qa_check(length(moved), NULL, stop = length(moved) > 0L,
                                   why = paste("records by source moved past their limits:", paste(moved, collapse = "; ")),
                                   detail = if (length(below_floor)) list(below_floor = as.list(below_floor)))

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
atlas_pull_qa <- function(occurrences, manifest, audit = NULL, kingdoms = NULL, left_out = NULL, quiet = FALSE) {
  previous <- if (file.exists(atlas_qa_path())) jsonlite::fromJSON(atlas_qa_path(), simplifyVector = TRUE)
  privacy <- if (file.exists(atlas_privacy_path())) {
    utils::read.delim(gzfile(atlas_privacy_path(), encoding = "UTF-8"), sep = "	", quote = "", comment.char = "",
                      na.strings = "", colClasses = "character", stringsAsFactors = FALSE)
  }
  exclusions <- tryCatch(atlas_exclusion_keys(), error = function(e) NULL)
  report <- atlas_qa_report(occurrences, manifest, audit, privacy, previous, kingdoms = kingdoms,
                            allow = atlas_kingdom_allow(), exclusions = exclusions, left_out = left_out)
  atlas_write_json(report, atlas_qa_path(manifest$stamp))
  atlas_write_json(report, atlas_qa_path())
  if (!is.null(left_out)) {
    new <- unlist(report$checks$kingdom_left_out$detail$new)
    # A note that cannot be written must not lose the report it repeats.
    tryCatch(atlas_note_left_out(left_out$names, new), error = function(e) {
      warning("left-out note not written: ", conditionMessage(e), call. = FALSE)
    })
    if (!isTRUE(quiet) && left_out$records > 0L) {
      message(sprintf("left out as not fungi: %d records of %d names; new: %s", left_out$records, nrow(left_out$names),
                      if (length(new)) paste(new, collapse = ", ") else "none"))
    }
  }
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
