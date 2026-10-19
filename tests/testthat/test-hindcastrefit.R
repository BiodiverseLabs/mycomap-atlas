# A hindcast refit: some of a finished hindcast's models fitted again
# without listed records, the hindcast's in everything else, the hindcast
# untouched (the paper's rule for a training record validated after the
# cutoff).

test_that("a hindcast refit leaves out exactly the listed records, and draws with the hindcast model's seed", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast()
  hind <- setup$hindcast
  gone <- pull_ids(setup$store, hind, "Taxon A")[c(2, 5)]
  refit <- plan_refit(setup, "Taxon A", gone)
  before <- job_pull(setup$store, hind)
  after <- job_pull(setup$store, refit)
  # The hindcast's pull but exactly those two rows.
  expect_setequal(as.character(after$id), setdiff(as.character(before$id), gone))
  expect_equal(nrow(after), nrow(before) - 2L)
  expect_identical(refit$filter$records_left_out, 2L)
  left <- refit$refit$left_out
  expect_setequal(vapply(left, function(r) r$id, ""), gone)
  # Each by its own key too: the source and the source's number.
  expect_setequal(vapply(left, function(r) paste(r$source, r$observation_id, sep = ":"), ""),
                  paste(before$source, before$observation_id, sep = ":")[before$id %in% gone])
  expect_true(all(vapply(left, function(r) identical(r$taxon, "Taxon A"), logical(1))))
  # Exactly the hindcast's models of the taxon, with its settings, layers
  # and inputs.
  expect_setequal(vapply(refit$tasks, function(t) t$taxon, ""), "Taxon A")
  expect_setequal(vapply(refit$tasks, function(t) t$algorithm, ""), hindcast_algorithms(setup, "Taxon A"))
  expect_identical(refit$fit, hind$fit)
  expect_identical(refit$layers_key, hind$layers_key)
  not_pull <- function(job) Filter(function(e) !startsWith(e$path, "occurrences/"), job$inputs)
  expect_identical(not_pull(refit), not_pull(hind))
  expect_identical(refit$validated_through, HINDCAST_CUTOFF)
  expect_identical(refit$kind, "private-release")
  # A model belongs to its record set: the refit's own fingerprint, drawn
  # with the hindcast model's seed.
  hind_a <- Filter(function(t) identical(t$taxon, "Taxon A"), hind$tasks)
  expect_true(all(vapply(refit$tasks, function(t) identical(t$seed_from, hind_a[[1]]$fingerprint), logical(1))))
  expect_false(any(vapply(refit$tasks, function(t) identical(t$fingerprint, t$seed_from), logical(1))))

  seen <- new.env()
  watch <- function(name, algorithm, points, training) {
    seen$points <- points
    seen$training <- training
  }
  run_private(setup$store, refit, seeded_fit(watch = watch))
  expect_identical(attr(seen$training, "seed"), atlas_seed_from_fingerprint(hind_a[[1]]$fingerprint))
  # The survey sites are the hindcast's, but for the left-out records' own
  # (each at a place of its own here): no detection, effort or background
  # site is built from them, and every other site counts what it did.
  hind_sites <- attr(atlas_ensure_sites(atlas_occurrence_points(before)), "sites")
  refit_sites <- attr(atlas_ensure_sites(seen$points), "sites")
  gone_cells <- atlas_occurrence_points(before[before$id %in% gone, ])$cell
  expect_setequal(setdiff(hind_sites$cell, refit_sites$cell), gone_cells)
  expect_length(setdiff(refit_sites$cell, hind_sites$cell), 0L)
  kept <- hind_sites[!hind_sites$cell %in% gone_cells, c("cell", "records")]
  expect_equal(refit_sites[match(kept$cell, refit_sites$cell), "records"], kept$records)
  expect_equal(sum(seen$training$presence == 1L), 30L - 2L)
})

test_that("a record is left out by its .org id or by its source and the source's number, the same record", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast()
  pull <- job_pull(setup$store, setup$hindcast)
  row <- which(pull$scientific_name == "Taxon A")[[4]]
  by_id <- plan_refit(setup, "Taxon A", as.character(pull$id[[row]]), dry_run = TRUE)
  by_source <- plan_refit(setup, "Taxon A", paste(pull$source[[row]], pull$observation_id[[row]], sep = ":"),
                          dry_run = TRUE)
  expect_identical(by_source$left_out, by_id$left_out)
  expect_identical(by_source$tasks, by_id$tasks)
  # The source's number alone names no record: the sources' numbers overlap.
  expect_identical(pull$id[[row]], pull$observation_id[[row]])
  expect_error(plan_refit(setup, "Taxon A", paste0("Elsewhere:", pull$observation_id[[row]]), dry_run = TRUE),
               "not in hindcast")
})

test_that("with nothing left out, a hindcast refit reproduces the hindcast's models byte for byte", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast()
  hind <- setup$hindcast
  refit <- plan_refit(setup, "Taxon B")
  strip <- function(tasks) lapply(tasks, function(t) t[c("taxon", "algorithm", "fingerprint")])
  order_of <- function(tasks) tasks[order(vapply(tasks, function(t) t$algorithm, ""))]
  expect_identical(strip(order_of(refit$tasks)),
                   strip(order_of(Filter(function(t) identical(t$taxon, "Taxon B"), hind$tasks))))
  run_private(setup$store, refit, seeded_fit(list("Taxon B" = "weak")))
  # Same pull, settings, seeds, folds and null draws: the same files, to
  # the byte, and the same index entries.
  original <- shard_models(setup$store, hind, "Taxon B")
  again <- shard_models(setup$store, refit, "Taxon B")
  expect_gt(length(original$files), 0L)
  strip_files <- function(files) lapply(files, function(f) f[c("path", "sha256")])
  expect_identical(strip_files(again$files), strip_files(original$files))
  expect_identical(again$index, original$index)
})

test_that("a refit's release is the hindcast's with only the refitted models swapped, every other file byte for byte", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast(grades = list("Taxon A" = "strong", "Taxon B" = "weak", "Taxon C" = "weak"))
  hind <- setup$hindcast
  gone <- pull_ids(setup$store, hind, "Taxon A")[[3]]
  refit <- plan_refit(setup, "Taxon A", gone, algorithms = "esm", validated_through = HINDCAST_CUTOFF,
                      reason = "first green date from another source's record", rule = "the 3 to 19 site rule")
  expect_identical(vapply(refit$tasks, function(t) t$algorithm, ""), "esm")
  run_private(setup$store, refit, seeded_fit(list("Taxon A" = "weak")))
  summary <- finish_private(setup$store, refit$id)
  source <- atlas_store_text(setup$store, atlas_benchmark_key(hind$id, "release.json"))
  manifest <- atlas_store_text(setup$store, atlas_benchmark_key(refit$id, "release.json"))
  owned <- function(path) startsWith(path, sub("json$", "", atlas_model_relpaths("Taxon A", algorithm = "esm",
                                                                                   extensions = ".json")))
  by_path <- function(files) stats::setNames(vapply(files, function(f) f$sha256, ""), vapply(files, function(f) f$path, ""))
  before <- by_path(source$files)
  after <- by_path(manifest$files)
  # Every path but the model's: there, with the hindcast's bytes.
  others <- names(before)[!vapply(names(before), owned, logical(1))]
  expect_gt(length(others), 10L)
  expect_identical(after[others], before[others])
  expect_setequal(names(after)[!vapply(names(after), owned, logical(1))], others)
  # The model's: there, and the refit's.
  swapped <- names(after)[vapply(names(after), owned, logical(1))]
  expect_setequal(swapped, names(before)[vapply(names(before), owned, logical(1))])
  expect_false(any(after[swapped] == before[swapped]))
  refit_files <- by_path(shard_models(setup$store, refit, "Taxon A")$files)
  expect_identical(after[swapped], refit_files[swapped])
  # Every index entry but the model's is the hindcast's; the model's is the
  # refit's, its own fingerprint, marked as a refit of the hindcast.
  key <- function(e) paste(e$algorithm, e$taxon)
  expect_identical(vapply(manifest$index, key, ""), vapply(source$index, key, ""))
  is_model <- vapply(manifest$index, key, "") == "esm Taxon A"
  expect_identical(manifest$index[!is_model], source$index[!is_model])
  entry <- manifest$index[is_model][[1]]
  expect_identical(entry$refit_of, hind$id)
  expect_identical(entry$fingerprint, refit$tasks[[1]]$fingerprint)
  expect_identical(entry$grade, "weak")
  # Its record names the hindcast, its job, the reason and rule, each record
  # by its keys, and both fits: fingerprints, grades and scores.
  for (record in list(summary$refit, manifest$refit)) {
    expect_identical(record$hindcast, hind$id)
    expect_identical(record$hindcast_job, hind$id)
    expect_identical(record$reason, "first green date from another source's record")
    expect_identical(record$rule, "the 3 to 19 site rule")
    expect_identical(record$left_out[[1]]$id, gone)
    expect_identical(record$left_out[[1]]$taxon, "Taxon A")
    expect_false(is.null(record$left_out[[1]]$source) || is.null(record$left_out[[1]]$observation_id))
    expect_length(record$models, 1L)
    m <- record$models[[1]]
    expect_identical(c(m$taxon, m$algorithm), c("Taxon A", "esm"))
    expect_identical(m$hindcast_fingerprint, refit$tasks[[1]]$seed_from)
    expect_identical(m$refit_fingerprint, refit$tasks[[1]]$fingerprint)
    expect_identical(c(m$hindcast$grade, m$refit$grade), c("strong", "weak"))
    expect_true(is.numeric(m$hindcast$auc_mean) && is.numeric(m$refit$auc_mean))
    expect_true(is.numeric(m$hindcast$boyce_pooled) && is.numeric(m$refit$boyce_pooled))
    expect_equal(m$refit$presences, m$hindcast$presences - 1)
  }
  # Its models table is the hindcast's with that row swapped and marked.
  hind_models <- atlas_private_models(setup$store, hind$id)
  refit_models <- atlas_private_models(setup$store, refit$id)
  row <- refit_models$taxon == "Taxon A" & refit_models$algorithm == "esm"
  expect_identical(refit_models$refit, row)
  expect_identical(refit_models$grade[row], "weak")
  rest <- refit_models[!row, names(hind_models)]
  rownames(rest) <- NULL
  expected <- hind_models[!(hind_models$taxon == "Taxon A" & hind_models$algorithm == "esm"), ]
  rownames(expected) <- NULL
  expect_identical(rest, expected)
  # Its trained records are the hindcast's: Taxon A's other models, kept,
  # were trained with that record too.
  expect_identical(atlas_read_trained_table(setup$store, atlas_trained_release_key(refit$id)),
                   atlas_read_trained_table(setup$store, atlas_trained_release_key(hind$id)))
  # The hindcast still has its own model, and a refit is never refitted.
  expect_true(all(hind_models$grade[hind_models$taxon == "Taxon A"] == "strong"))
  expect_error(on_machine(setup$boss, atlas_plan_hindcast_refit(setup$store, refit$id, "Taxon A", reason = "x",
                                                                quiet = TRUE)), "not a hindcast")
})

test_that("a hindcast refit never writes the hindcast, its pull, the box's pull or anything public", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast()
  hind <- setup$hindcast
  inputs <- vapply(Filter(function(e) startsWith(e$path, "occurrences/"), hind$inputs),
                   function(e) atlas_object_key(e$sha256), "")
  watched <- c(atlas_benchmark_key(hind$id, ""), paste0("jobs/draft/", hind$id, "/"), "releases/", "current/",
               "promotions/", "public/", inputs, atlas_trained_release_key(hind$id))
  store_before <- store_snapshot(setup$store, watched)
  all_keys <- function() sub("^/", "", setup$store$list(""))
  keys_before <- all_keys()
  box_before <- dir_snapshot(setup$boss)
  gone <- pull_ids(setup$store, hind, "Taxon A")[[1]]
  refit <- plan_refit(setup, "Taxon A", gone)
  run_private(setup$store, refit, seeded_fit())
  finish_private(setup$store, refit$id)
  # The hindcast's files, its job, its pull and the pull's manifest: the
  # same bytes; nothing new in releases/, current/, promotions/ or public/.
  expect_identical(store_snapshot(setup$store, watched), store_before)
  # Everything it wrote is an object, its own job's, or private.
  added <- setdiff(all_keys(), keys_before)
  expect_gt(length(added), 0L)
  expect_true(all(grepl(paste0("^(objects/|jobs/draft/(finish-)?", refit$id, "/|private/)"), added)), info = paste(added, collapse = ", "))
  expect_true(any(startsWith(added, atlas_benchmark_key(refit$id, ""))))
  # The box's data directory, its pull among it, and no drop list.
  expect_identical(dir_snapshot(setup$boss), box_before)
  # Every model of Taxon A refitted: trained on the hindcast's records but
  # that one, privately.
  trained <- atlas_read_trained_table(setup$store, atlas_trained_release_key(refit$id))
  hind_trained <- atlas_read_trained_table(setup$store, atlas_trained_release_key(hind$id))
  pull <- job_pull(setup$store, hind)
  gone_key <- as.character(pull$observation_id[pull$id == gone])
  expect_equal(nrow(trained), nrow(hind_trained) - 1L)
  expect_false(gone_key %in% trained$source_id[trained$taxon == "Taxon A"])
  expect_true(gone_key %in% hind_trained$source_id[hind_trained$taxon == "Taxon A"])
  expect_false(file.exists(file.path(setup$boss, "occurrences", "exclude.tsv")))
  expect_false(identical(atlas_job_pull_entry(refit)$sha256, atlas_job_pull_entry(hind)$sha256))
  expect_identical(refit$from_pull$sha256, atlas_job_pull_entry(hind)$sha256)
})

test_that("a hindcast refit refuses a record not in the pull or another taxon's, and a taxon or model it cannot swap", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast(refuse = list("Taxon A" = "rf"), ensembles = ensemble_for_b)
  hind <- setup$hindcast
  jobs_before <- setup$store$list("jobs/")
  a <- pull_ids(setup$store, hind, "Taxon A")
  # Validated after the cutoff, so in the release's pull and not the hindcast's.
  occ <- hindcast_occurrences()
  late <- occ$id[occ$scientific_name == "Taxon A" & occ$first_green_on > HINDCAST_CUTOFF][[1]]
  expect_error(plan_refit(setup, "Taxon A", c(a[[1]], late)), paste0("not in hindcast .*'s pull: ", late, " "))
  expect_error(plan_refit(setup, "Taxon A", "no-such-record"), "not in hindcast")
  expect_error(plan_refit(setup, "Taxon A", pull_ids(setup$store, hind, "Taxon B")[[1]]),
               "Taxon B's, not a named taxon's")
  expect_error(plan_refit(setup, c("Taxon A", "Taxon Zed"), a[[1]]), "no model of Taxon Zed")
  # Taxon C has records in the pull and no model (its fits found no sites
  # within reach): nothing to swap.
  expect_error(plan_refit(setup, "Taxon C", pull_ids(setup$store, hind, "Taxon C")[[1]]), "no model of Taxon C")
  # Its rf model was refused: there is none to swap.
  expect_error(plan_refit(setup, "Taxon A", a[[1]], algorithms = "rf"), "no rf model of Taxon A")
  # Taxon B has a combined map, which a swap would leave stale.
  expect_error(plan_refit(setup, "Taxon B", pull_ids(setup$store, hind, "Taxon B")[[1]]), "combined map")
  expect_error(plan_refit(setup, "Taxon A", a[[1]], validated_through = "2026-09-30"), "not the hindcast's cutoff")
  expect_error(plan_refit(setup, "Taxon A", a[[1]], reason = ""), "needs --reason")
  expect_error(plan_refit(setup, character()), "needs --taxa")
  # The release it was made from is not a hindcast.
  expect_error(on_machine(setup$boss, atlas_plan_hindcast_refit(setup$store, setup$main$id, "Taxon A", reason = "x",
                                                                quiet = TRUE)), "no finished private release")
  expect_identical(setup$store$list("jobs/"), jobs_before)
})

test_that("a hindcast refit refuses a model whose taxon falls below the algorithm's minimum without the records", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast()
  hind <- setup$hindcast
  jobs_before <- setup$store$list("jobs/")
  # Taxon B has 25 sites in the hindcast: six fewer is under Maxent's 20,
  # and its Maxent model could not be swapped, so nothing is refitted.
  b6 <- pull_ids(setup$store, hind, "Taxon B")[1:6]
  expect_true("maxnet" %in% hindcast_algorithms(setup, "Taxon B"))
  expect_error(plan_refit(setup, "Taxon B", b6), "Taxon B has 19 sites, outside maxnet's 20 to")
  expect_identical(setup$store$list("jobs/"), jobs_before)
})

test_that("a hindcast refit is planned only from a finished hindcast", {
  skip_if_not_installed("terra")
  setup <- hindcast_setup()
  hind <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                            HINDCAST_CUTOFF, shards = 1L, quiet = TRUE))
  run_private(setup$store, hind, seeded_fit())
  setup$hindcast <- hind
  a <- pull_ids(setup$store, hind, "Taxon A")[[1]]
  # Fitted, not finished: still running, as far as anyone can tell.
  expect_error(plan_refit(setup, "Taxon A", a), "no finished private release")
  finish_private(setup$store, hind$id)
  # A manifest without the summary written last is not finished either.
  summary <- file.path(sub("^file://", "", setup$store$uri), atlas_benchmark_key(hind$id, "summary.json"))
  saved <- readLines(summary)
  file.remove(summary)
  expect_error(plan_refit(setup, "Taxon A", a), "no finished private release")
  writeLines(saved, summary)
  expect_identical(plan_refit(setup, "Taxon A", a, dry_run = TRUE)$filter$records_left_out, 1L)
})

test_that("a dry run of a hindcast refit writes nothing", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast()
  hind <- setup$hindcast
  before <- c(setup$store$list("jobs/"), setup$store$list("objects/"), setup$store$list("private/"))
  dry <- plan_refit(setup, "Taxon A", pull_ids(setup$store, hind, "Taxon A")[[1]], reason = NULL, dry_run = TRUE)
  expect_identical(c(setup$store$list("jobs/"), setup$store$list("objects/"), setup$store$list("private/")), before)
  expect_identical(dry$filter$records_left_out, 1L)
  expect_gt(dry$estimate$models, 0L)
})

test_that("--taxa and --leave-out refit only a hindcast, and only with both", {
  store <- machine()
  run <- function(...) atlas_main(c("plan-job", paste0("--store=", store), ...))
  expect_error(run("--taxa=Taxon A", "--leave-out=1"), "need --hindcast")
  expect_error(run("--leave-out=1"), "need --hindcast")
  expect_error(run("--record-names", "--from-release=R", "--taxa=Taxon A", "--leave-out=1"), "need --hindcast")
  expect_error(run("--prior-only", "--from-release=R", "--validated-through=2026-08-17", "--leave-out=1"),
               "need --hindcast")
  expect_error(run("--hindcast", "--from-release=priv-1", "--taxa=Taxon A"), "needs --taxa=.* and --leave-out")
  expect_error(run("--hindcast", "--from-release=priv-1", "--leave-out=1"), "needs --taxa=.* and --leave-out")
  expect_error(run("--hindcast", "--taxa=Taxon A", "--leave-out=1"), "needs --from-release")
})

test_that("the command line plans a hindcast refit from the hindcast's id, names, record keys and reason", {
  skip_if_not_installed("terra")
  setup <- finished_hindcast()
  hind <- setup$hindcast
  pull <- job_pull(setup$store, hind)
  a <- which(pull$scientific_name == "Taxon A")[c(1, 4)]
  keys <- c(as.character(pull$id[[a[[1]]]]), paste(pull$source[[a[[2]]]], pull$observation_id[[a[[2]]]], sep = ":"))
  args <- c("plan-job", paste0("--store=", setup$store$uri), "--hindcast", paste0("--from-release=", hind$id),
            paste0("--validated-through=", HINDCAST_CUTOFF), "--taxa=Taxon A", "--algorithms=esm",
            paste0("--leave-out=", paste(keys, collapse = ",")))
  expect_error(on_machine(setup$boss, atlas_main(args)), "needs --reason")
  suppressMessages(on_machine(setup$boss, atlas_main(c(args, "--reason=a test", "--rule=the site rule"))))
  ids <- unique(basename(dirname(grep("/job[.]json$", setup$store$list("jobs/draft/"), value = TRUE))))
  jobs <- Filter(function(j) !is.null(j$refit), lapply(ids, function(id) atlas_read_job(setup$store, id)))
  expect_length(jobs, 1L)
  expect_setequal(vapply(jobs[[1]]$refit$left_out, function(r) r$id, ""), as.character(pull$id[a]))
  expect_identical(jobs[[1]]$refit$reason, "a test")
  expect_identical(jobs[[1]]$refit$rule, "the site rule")
  expect_identical(vapply(jobs[[1]]$tasks, function(t) t$algorithm, ""), "esm")
})

test_that("a fit drawn with another record set's seed draws as that record set's fit does", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  # A fit seeds the session's generator, which machine() names later tests'
  # data directories from: put it back as it was.
  state <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  on.exit(if (is.null(state)) rm(".Random.seed", envir = globalenv()) else
    assign(".Random.seed", state, envir = globalenv()), add = TRUE)
  world <- synthetic_landscape()
  focal <- which(world$points$scientific_name == "Eastern fungus")
  world$points <- world$points[-focal[-seq_len(12)], , drop = FALSE]
  fit <- function(...) on_machine(machine(), atlas_fit_taxon(
    "Eastern fungus", points = world$points, stack = world$stack, layers = "synthetic", n_background = 500,
    buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 0, algorithm = "esm",
    guilds = stats::setNames(character(), character()), ...)$metrics)
  own <- fit(fingerprint = "f00dfeed")
  borrowed <- fit(fingerprint = "0badcafe", seed_from = "f00dfeed")
  plain <- fit(fingerprint = "0badcafe")
  expect_identical(borrowed$seed, own$seed)
  expect_false(identical(plain$seed, own$seed))
  # The model is its own record set's, drawn as the other's was.
  expect_identical(borrowed$fingerprint, "0badcafe")
  same <- c("folds", "auc_mean", "params", "block_km", "presence_blocks")
  expect_identical(borrowed[same], own[same])
})
