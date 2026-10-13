# Study jobs: a paper experiment's command, sharded onto the EC2 machinery
# production jobs use (Steve, 2026-10-13; Atlas E1, E1c, E6a and the like
# run to thousands of CPU-hours, past what a PC can do).
#
# A study command (R/study*.R, the experiments lane) takes --shard=i/n and
# --out=<prefix>, and publishes its own results under that prefix, which its
# guard holds to study/ or private/. A study job runs one shard of it per
# worker, from the same image, with the inputs of a release's job fetched
# first when it names one (the pull, the layers, the FungalTraits table):
#
#   ./atlas plan-study --command=study-rescan --shards=4 [--from-release=ID] [--args="--release=ID --sample=200"]
#   ./atlas run-job-ec2 --job=<ID>      (a worker per shard: ./atlas run-study --job=<ID> --shard=<n>)
#
# Its results go under study/<id>/. Nothing it does is a release: no
# release, current pointer, promotion or private file of production's is
# written, and finish-job refuses it. A worker may write study/ only by the
# grant in deploy/aws/worker/permissions.json; production never reads there.
# Each shard writes a record when its command returns, as a fitting shard
# does, saying whether it succeeded; the job succeeds when every one did.

ATLAS_STUDY_PREFIX <- "study"

atlas_is_study_job <- function(job) identical(job$kind, "study")

#' The commands atlas_main knows: the names of the switch it dispatches on.
atlas_cli_commands <- function() {
  find <- function(e) {
    if (is.call(e)) {
      if (identical(e[[1]], as.name("switch"))) return(setdiff(names(as.list(e)), ""))
      for (part in as.list(e)) {
        found <- find(part)
        if (length(found)) return(found)
      }
    }
    character()
  }
  find(body(atlas_main))
}

#' Plan a study job: a study command and its arguments, in n shards, with a
#' release's job inputs fetched first when from_release is given.
atlas_plan_study_job <- function(store = atlas_store(), command, args = character(), shards = 4L,
                                 from_release = NULL, grid = "draft", quiet = FALSE,
                                 commands = atlas_cli_commands()) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (!is.character(command) || length(command) != 1L || !grepl("^study-[a-z0-9-]+$", command)) {
    stop("a study job runs a study command (study-...), not ", command %||% "nothing", call. = FALSE)
  }
  if (!command %in% commands) stop("there is no command ", command, " in this version", call. = FALSE)
  args <- as.character(args)
  if (any(grepl("^--(shard|out)(=|$)", args))) {
    stop("a study job sets --shard and --out itself", call. = FALSE)
  }
  shards <- as.integer(shards)
  if (is.na(shards) || shards < 1L) stop("shards must be a positive number", call. = FALSE)
  inputs <- list()
  if (!is.null(from_release)) {
    key <- paste0("releases/", grid, "/", from_release, ".json")
    if (!store$exists(key)) stop("no release ", from_release, " for the ", grid, " grid", call. = FALSE)
    job_id <- atlas_json_string(atlas_store_text(store, key)$job)
    if (is.null(job_id)) stop("release ", from_release, " was not made by a job", call. = FALSE)
    inputs <- atlas_read_job(store, job_id, grid)$inputs %||% list()
  }
  id <- paste0("study-", atlas_release_id(digest::digest(list(command, args, shards, from_release),
                                                         algo = "sha256")))
  job <- list(
    id = id, grid = grid, kind = "study",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    command = command, args = as.list(args), shards = shards,
    out = paste0(ATLAS_STUDY_PREFIX, "/", id, "/"),
    from_release = from_release, inputs = inputs,
    tasks = list(), retire = list(), public = list(), deferred = 0L
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
  say("study job ", id, ": ", command, " in ", shards, " shard", if (shards == 1L) "" else "s",
      "; results under ", job$out)
  invisible(job)
}

#' On a worker: run one shard of a study job, and record whether it
#' succeeded. main is atlas_main (replaceable for tests).
atlas_run_study_shard <- function(store = atlas_store(), id, shard, grid = "draft", quiet = FALSE, main = atlas_main) {
  job <- atlas_read_job(store, id, grid)
  if (!atlas_is_study_job(job)) stop("job ", id, " is not a study job", call. = FALSE)
  shard <- as.integer(shard)
  if (is.na(shard) || shard < 1L || shard > job$shards) stop("job ", id, " has no shard ", shard, call. = FALSE)
  started <- Sys.time()
  atlas_fetch_entries(store, job$inputs %||% list())
  argv <- c(job$command, unlist(job$args), sprintf("--shard=%d/%d", shard, as.integer(job$shards)),
            paste0("--out=", job$out))
  outcome <- tryCatch({
    code <- main(argv)
    if (is.numeric(code) && length(code) == 1L && code != 0) {
      list(status = "failed", error = paste("exit code", code))
    } else {
      list(status = "succeeded")
    }
  }, error = function(e) list(status = "failed", error = conditionMessage(e)))
  record <- c(list(job = id, shard = shard, machine = atlas_machine_info(), command = paste(argv, collapse = " "),
                   started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                   finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")), outcome)
  atlas_store_json(store, atlas_shard_key(id, shard, grid), record)
  if (!isTRUE(quiet)) message("study shard ", shard, " of ", id, ": ", outcome$status,
                              if (!is.null(outcome$error)) paste0(" (", outcome$error, ")"))
  invisible(record)
}

#' Once every shard of a study job has reported: its outcome. Stops, naming
#' them, when any shard failed.
atlas_study_outcome <- function(store, job, grid = "draft") {
  records <- lapply(seq_len(job$shards), function(n) atlas_store_text(store, atlas_shard_key(job$id, n, grid)))
  failed <- Filter(function(r) !identical(r$status, "succeeded"), records)
  if (length(failed)) {
    stop("study job ", job$id, ": shard", if (length(failed) > 1L) "s " else " ",
         paste(vapply(failed, function(r) paste0(r$shard, " (", r$error %||% "no reason", ")"), ""), collapse = ", "),
         " failed; results of the others are under ", job$out, call. = FALSE)
  }
  list(job = job$id, shards = job$shards, out = job$out, command = job$command)
}
