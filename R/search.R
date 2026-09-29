# Finding a taxon by what someone types.
#
# People type names the way they remember them: lower case, without the
# quotes of a provisional code, with a letter wrong, the epithet first, or
# only the start of a word. A name written three ways on .org should be found
# whichever way it is typed. So matching runs on a search key — lower case,
# letters and digits only, rank words and "sp." dropped — and falls back from
# exact, to prefix, to every word, to anywhere, to a near miss.
#
# The key is for matching only. It never renames or merges anything: that is
# R/names.R's job, done on the records. Letters and digits are kept exactly,
# so 'IN1' and 'IN01' stay different names (a near miss at best).

# Words that say what kind of name it is, not which one.
ATLAS_SEARCH_NOISE <- c("sp", "spp", "cf", "aff", "var", "subsp", "ssp", "f", "forma")

ATLAS_SEARCH_TIERS <- c("exact", "prefix", "words", "contains", "similar")

#' The search key of a name or a query.
atlas_search_key <- function(x) {
  x <- tolower(enc2utf8(as.character(x)))
  tokens <- strsplit(gsub("[^a-z0-9]+", " ", x), " ", fixed = TRUE)
  vapply(tokens, function(t) {
    t <- t[nzchar(t) & !t %in% ATLAS_SEARCH_NOISE]
    paste(t, collapse = " ")
  }, character(1), USE.NAMES = FALSE)
}

#' Everything a search needs from the taxon table, computed once.
atlas_search_index <- function(taxa) {
  keys <- atlas_search_key(taxa$scientific_name)
  tokens <- strsplit(keys, " ", fixed = TRUE)
  genus <- sub(" .*$", "", trimws(taxa$scientific_name))
  flat <- unlist(tokens)
  list(
    taxa = taxa,
    keys = keys,
    tokens = tokens,
    # Every word of every name, and which taxon it belongs to: matching a word
    # is then one vectorised lookup rather than a loop over seventeen thousand.
    flat = flat,
    owner = rep(seq_along(tokens), lengths(tokens)),
    first = vapply(tokens, function(t) if (length(t)) t[[1]] else "", character(1)),
    vocab = sort(unique(flat)),
    genus = genus,
    genus_key = atlas_search_key(genus)
  )
}

#' How far apart two words are, forgiving a word typed only partly: the
#' distance to the whole word or to its start, whichever is smaller.
atlas_search_near <- function(query_token, vocab) {
  n <- nchar(query_token)
  if (n < 4L) return(character())
  allowed <- if (n >= 7L) 2L else 1L
  # A word more than the allowance longer or shorter cannot be within it,
  # unless the query is only its start.
  vocab <- vocab[nchar(vocab) >= n - allowed]
  if (!length(vocab)) return(character())
  whole <- utils::adist(query_token, vocab)[1, ]
  start <- utils::adist(query_token, substr(vocab, 1L, n))[1, ]
  vocab[pmin(whole, start) <= allowed]
}

#' Rank taxa against a query. mapped is a named list: taxon -> algorithms
#' with a map. Returns up to limit species and a few genera.
atlas_search <- function(index, query, mapped = list(), limit = 10L, genera = 3L) {
  q <- atlas_search_key(query)
  empty <- list(query = as.character(query), species = index$taxa[0, , drop = FALSE], genera = list())
  if (!nzchar(q)) return(empty)
  q_tokens <- strsplit(q, " ", fixed = TRUE)[[1]]

  tier <- rep(NA_integer_, length(index$keys))
  set <- function(which, value) tier[which & is.na(tier)] <<- value
  set(index$keys == q, 1L)
  set(startsWith(index$keys, q), 2L)
  # Taxa that have, for every word typed, a word in one of the given sets.
  having_all <- function(word_sets) {
    hit <- rep(TRUE, length(index$keys))
    for (words in word_sets) {
      mine <- rep(FALSE, length(index$keys))
      mine[unique(index$owner[index$flat %in% words])] <- TRUE
      hit <- hit & mine
    }
    hit
  }
  starts <- lapply(q_tokens, function(qt) index$vocab[startsWith(index$vocab, qt)])
  set(having_all(starts), 3L)
  set(grepl(q, index$keys, fixed = TRUE), 4L)
  # Near misses only when the closer matches leave room: they are the costly part.
  if (sum(!is.na(tier)) < limit) {
    near <- Map(function(qt, starting) c(atlas_search_near(qt, index$vocab), starting), q_tokens, starts)
    set(having_all(near), 5L)
  }

  hits <- which(!is.na(tier))
  has_map <- index$taxa$scientific_name[hits] %in% names(mapped)
  # Within a tier, a name whose genus is what was typed first comes before
  # one where it is only the epithet: cantharellus means the chanterelles
  # before Hygrocybe cantharellus.
  first <- index$first[hits]
  lead <- q_tokens[[1]]
  genus_hit <- first == lead | startsWith(first, lead) |
    (nchar(lead) >= 4L & first %in% atlas_search_near(lead, unique(first)))
  # Then the name closest to what was typed: amanita musc means Amanita
  # muscaria before its varieties. Only then maps first, then the best recorded.
  extra <- lengths(index$tokens[hits]) - length(q_tokens)
  order <- order(tier[hits], !genus_hit, extra, !has_map, -index$taxa$localities[hits],
                 index$taxa$scientific_name[hits])
  hits <- utils::head(hits[order], limit)

  species <- index$taxa[hits, c("scientific_name", "records", "localities"), drop = FALSE]
  rownames(species) <- NULL
  species$models <- lapply(species$scientific_name, function(n) as.character(mapped[[n]] %||% character()))
  species$match <- ATLAS_SEARCH_TIERS[tier[hits]]

  list(query = as.character(query), species = species,
       genera = atlas_search_genera(index, q_tokens, mapped, genera))
}

#' Genera a one-word query could mean: by prefix, or a near miss.
atlas_search_genera <- function(index, q_tokens, mapped, limit = 3L) {
  if (length(q_tokens) != 1L || limit < 1L) return(list())
  qt <- q_tokens[[1]]
  keys <- unique(index$genus_key)
  hit <- keys[startsWith(keys, qt)]
  if (!length(hit)) hit <- intersect(keys, atlas_search_near(qt, keys))
  if (!length(hit)) return(list())
  rows <- lapply(hit, function(k) {
    mine <- index$genus_key == k
    names <- index$taxa$scientific_name[mine]
    list(
      genus = index$genus[mine][[1]],
      taxa = sum(mine),
      mapped = sum(names %in% names(mapped)),
      records = sum(index$taxa$records[mine])
    )
  })
  rows <- rows[order(-vapply(rows, `[[`, numeric(1), "records"))]
  utils::head(rows, limit)
}

#' Which taxa have a map, and from which models: taxon -> algorithms.
atlas_search_mapped <- function(models) {
  if (is.null(models) || !nrow(models)) return(list())
  models <- models[models$map, , drop = FALSE]
  split(models$algorithm, models$taxon)
}
