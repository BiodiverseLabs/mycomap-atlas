# Running a job on EC2.
#
# The always-on box is small (2 GB) and does no fitting. When a plan has work,
# it launches one EC2 spot instance per shard. Each worker boots, installs
# Docker, pulls the release image built from the same commit as the
# orchestrator, runs its shard, uploads its log, and shuts itself down — which
# terminates it. A shutdown timer set at boot does the same if anything hangs,
# so a stuck worker cannot bill past the job's deadline.
#
# Workers reach the store with an instance role; no keys ever go on an
# instance. Spot capacity can be reclaimed at any moment, so a shard whose
# instance disappears without reporting is launched again, up to a limit. When
# spot capacity is short, a launch tries every allowed instance type in every
# subnet, and if all of them refuse, tries again at the next poll. If the whole
# job overruns its deadline, or the orchestrator itself fails, every worker is
# terminated and the job is left unfinished: the next plan picks the same work
# up, because nothing in the current release changed.
#
# What the orchestrator may do is fixed in AWS as well as here: the IAM policy
# in deploy/aws/orchestrator/ only allows tagged launches of the allowed
# types with the worker's profile, so a bug here fails closed.
#
# Workers are spot by default. ATLAS_EC2_MARKET=on-demand launches every
# worker on demand instead, and ATLAS_EC2_FINISH_MARKET the finishing worker
# alone (a release's finish, a prior-only or private release's): one long
# worker whose reclaim costs hours, while shards stay cheap. An on-demand
# worker is the same request without the spot options: same tags, types and
# their order, shutdown timer and deadline.
#
# The EC2 client is replaceable, which is how the tests run whole jobs — spot
# reclaims and all — without AWS.

ATLAS_EC2_MARKETS <- c("spot", "on-demand")

#' A market setting, refusing anything but spot or on-demand.
atlas_ec2_market <- function(value, name = "ATLAS_EC2_MARKET") {
  value <- tolower(trimws(as.character(value %||% "spot")))
  if (!value %in% ATLAS_EC2_MARKETS) {
    stop(name, " must be spot or on-demand, not '", value, "'", call. = FALSE)
  }
  value
}

ATLAS_EC2_REQUIRED <- c(
  "ATLAS_STORE", "ATLAS_EC2_REGION", "ATLAS_EC2_SUBNETS",
  "ATLAS_EC2_SECURITY_GROUP", "ATLAS_EC2_INSTANCE_PROFILE"
)

# The newest Amazon Linux 2023, looked up by EC2 at launch, so a worker never
# boots an image that has gone stale in a config file.
ATLAS_EC2_DEFAULT_AMI <- "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

# Spot launch errors that another instance type or zone may not have. Quota
# and permission errors are not here: trying elsewhere cannot fix them.
ATLAS_EC2_CAPACITY_ERRORS <- c(
  "InsufficientInstanceCapacity", "InsufficientCapacity", "InsufficientHostCapacity",
  "SpotMaxPriceTooLow", "Unsupported", "InsufficientFreeAddressesInSubnet"
)

# EC2's own failures (HTTP 5xx): its side, not ours, and gone a moment later.
# One of them stopped E1's first full run on 2026-10-25 and took its four
# running workers with it.
ATLAS_EC2_TRANSIENT_ERRORS <- c("InternalError", "InternalFailure", "ServiceUnavailable", "Unavailable")

# Errors that mean "not now": retry at the next poll rather than fail the job.
ATLAS_EC2_RETRY_ERRORS <- c(ATLAS_EC2_CAPACITY_ERRORS, "MaxSpotInstanceCountExceeded",
                            "VcpuLimitExceeded", "RequestLimitExceeded", ATLAS_EC2_TRANSIENT_ERRORS)

# Polls in a row EC2 may fail to answer before the job is stopped: an outage
# that long is not a hiccup.
ATLAS_EC2_MAX_UNANSWERED <- 30L

#' A comma-separated setting as a character vector.
atlas_split_setting <- function(value) {
  parts <- trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1]])
  parts[nzchar(parts)]
}

#' How to launch workers, from the environment. Refuses, naming every missing
#' setting, rather than launching something half-configured.
atlas_ec2_config <- function(env = function(name, unset = "") Sys.getenv(name, unset = unset),
                             commit = atlas_code_commit()) {
  missing <- ATLAS_EC2_REQUIRED[!nzchar(vapply(ATLAS_EC2_REQUIRED, env, character(1)))]
  if (length(missing)) {
    stop("EC2 is not configured; set ", paste(missing, collapse = ", "),
         " (see deploy/aws/README.md)", call. = FALSE)
  }
  image <- env("ATLAS_IMAGE", "")
  if (!nzchar(image)) {
    if (is.na(commit) || !grepl("^[0-9a-f]{40}$", commit)) {
      stop("cannot tell which image workers should run: this checkout has no commit; ",
           "set ATLAS_COMMIT or ATLAS_IMAGE", call. = FALSE)
    }
    # The image built from the orchestrator's own commit, so workers run
    # exactly the code that planned the job.
    image <- paste0("ghcr.io/biodiverselabs/mycomap-atlas:", commit)
  }
  number <- function(name, default) {
    value <- suppressWarnings(as.numeric(env(name, as.character(default))))
    if (is.na(value) || value <= 0) stop(name, " must be a positive number", call. = FALSE)
    value
  }
  list(
    store = env("ATLAS_STORE"),
    region = env("ATLAS_EC2_REGION"),
    ami = env("ATLAS_EC2_AMI", ATLAS_EC2_DEFAULT_AMI),
    subnets = atlas_split_setting(env("ATLAS_EC2_SUBNETS")),
    security_group = env("ATLAS_EC2_SECURITY_GROUP"),
    instance_profile = env("ATLAS_EC2_INSTANCE_PROFILE"),
    instance_types = atlas_split_setting(env("ATLAS_EC2_INSTANCE_TYPES", "c7a.8xlarge,c7i.8xlarge,m7a.8xlarge")),
    # Spot unless told otherwise; the finishing worker follows the shards
    # unless it has a market of its own.
    market = atlas_ec2_market(env("ATLAS_EC2_MARKET", "spot")),
    finish_market = atlas_ec2_market(env("ATLAS_EC2_FINISH_MARKET", env("ATLAS_EC2_MARKET", "spot")),
                                     "ATLAS_EC2_FINISH_MARKET"),
    image = image,
    max_workers = number("ATLAS_EC2_MAX_WORKERS", 4),
    max_hours = number("ATLAS_EC2_MAX_HOURS", 6),
    max_attempts = number("ATLAS_EC2_MAX_ATTEMPTS", 3),
    # How long a finishing worker (R/finish.R) may take: counting thousands of
    # maps by state the first time, then the could-grow-here index.
    finish_hours = number("ATLAS_EC2_FINISH_HOURS", 3),
    volume_gb = number("ATLAS_EC2_VOLUME_GB", 60),
    # Memory a worker allows each fit it runs at once (it runs RAM / this,
    # at most one per core). A widespread taxon's Maxent fit, its background
    # at the 10,000-site cap, peaked at 8.9 GB tuning (Trametes versicolor,
    # 2026-10-13), and a shard fits its richest taxa first, so at 3 GB a
    # 64 GB worker ran 21 of them at once and lost R processes to the
    # kernel's OOM killer (job 20261013T001819Z-2cb67f32, 566 of 1,231
    # failed). Set it from the box's environment, without a new image.
    gb_per_fit = number("ATLAS_EC2_GB_PER_FIT", 3)
  )
}

#' The script a worker runs at boot. `minutes` is how long it may live: the
#' time left before the job's deadline.
# How often a running worker uploads its logs, in seconds.
ATLAS_WORKER_LOG_SECONDS <- 300L

atlas_worker_user_data <- function(job_id, shard, grid, config, minutes = config$max_hours * 60,
                                   command = NULL) {
  store <- config$store
  # A fitting worker runs its shard; a finishing worker (R/finish.R) is
  # given its own command.
  command <- command %||% sprintf("run-shard --grid=%s --job=%s --shard=%d --workers=$WORKERS",
                                  grid, job_id, as.integer(shard))
  logs <- if (grepl("^s3://", store)) sprintf("%s/jobs/%s/%s/logs", sub("/$", "", store), grid, job_id)
  paste(c(
    "#!/bin/bash",
    "# MycoMap Atlas worker. Runs one shard of a job, then shuts down (which",
    "# terminates this instance).",
    "set -uxo pipefail",
    sprintf("shutdown -h +%d  # the deadline: a hung worker stops billing",
            max(1L, as.integer(ceiling(minutes)))),
    "exec > /var/log/atlas-worker.log 2>&1",
    "dnf install -y docker",
    "systemctl start docker",
    sprintf("docker pull %s", config$image),
    "mkdir -p /data && chown 10001:10001 /data",
    # The log, and the fits' own progress logs, go up every 5 minutes while
    # the shard runs: a worker stopped at the deadline (terminated, not shut
    # down) never reaches the upload at the end, and its log was lost (the
    # 2026-10-12 pilot).
    if (!is.null(logs)) {
      sprintf(paste("( while sleep %d; do aws s3 cp --quiet /var/log/atlas-worker.log %s/%d.log;",
                    "aws s3 sync --quiet --exclude '*' --include '*.log' /data/batches/ %s/%d-batches/; done ) &"),
              ATLAS_WORKER_LOG_SECONDS, logs, as.integer(shard), logs, as.integer(shard))
    },
    sprintf("# One fit per ~%s GB of memory, at most one per core.", format(config$gb_per_fit %||% 3)),
    sprintf("WORKERS=$(( $(free -g | awk '/^Mem:/{print $2}') / %d ))", as.integer(ceiling(config$gb_per_fit %||% 3))),
    "[ \"$WORKERS\" -gt \"$(nproc)\" ] && WORKERS=$(nproc)",
    "[ \"$WORKERS\" -lt 1 ] && WORKERS=1",
    "# The instance type, for the shard's record (IMDSv2).",
    paste("TYPE=$(curl -s -m 5 -H \"X-aws-ec2-metadata-token: $(curl -s -m 5 -X PUT",
          "-H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token)\"",
          "http://169.254.169.254/latest/meta-data/instance-type || true)"),
    sprintf("docker run --rm -v /data:/data -e ATLAS_STORE=%s -e AWS_REGION=%s -e ATLAS_INSTANCE_TYPE=\"$TYPE\" %s %s",
            shQuote(store), shQuote(config$region), config$image, command),
    "STATUS=$?",
    if (!is.null(logs)) {
      sprintf("aws s3 cp /var/log/atlas-worker.log %s/%d.log || true", logs, as.integer(shard))
    },
    sprintf("echo \"%s exited $STATUS\"", sub(" .*$", "", command)),
    "shutdown -h now"
  ), collapse = "\n")
}

#' The RunInstances request for one worker in one subnet with one type. A
#' spot request (the default) carries its market options; an on-demand one
#' is the same request without them.
atlas_worker_request <- function(config, job_id, shard, grid, attempt = 1L, subnet, instance_type,
                                 minutes = config$max_hours * 60, command = NULL,
                                 market = config$market %||% "spot") {
  tags <- list(
    list(Key = "Name", Value = sprintf("atlas-%s-shard-%d", job_id, as.integer(shard))),
    list(Key = "atlas", Value = "worker"),
    list(Key = "atlas-job", Value = job_id),
    list(Key = "atlas-shard", Value = as.character(shard)),
    list(Key = "atlas-attempt", Value = as.character(attempt))
  )
  user_data <- atlas_worker_user_data(job_id, shard, grid, config, minutes, command = command)
  request <- list(
    ImageId = config$ami,
    InstanceType = instance_type,
    MinCount = 1, MaxCount = 1,
    SubnetId = subnet,
    SecurityGroupIds = list(config$security_group),
    IamInstanceProfile = list(Name = config$instance_profile),
    UserData = jsonlite::base64_enc(charToRaw(user_data)),
    InstanceInitiatedShutdownBehavior = "terminate",
    InstanceMarketOptions = list(
      MarketType = "spot",
      SpotOptions = list(SpotInstanceType = "one-time", InstanceInterruptionBehavior = "terminate")
    ),
    # IMDSv2 only, and a hop limit of 2 so the container can reach the
    # instance role's credentials.
    MetadataOptions = list(HttpTokens = "required", HttpPutResponseHopLimit = 2),
    BlockDeviceMappings = list(list(
      DeviceName = "/dev/xvda",
      Ebs = list(VolumeSize = as.integer(config$volume_gb), VolumeType = "gp3", DeleteOnTermination = TRUE)
    )),
    TagSpecifications = list(
      list(ResourceType = "instance", Tags = tags),
      list(ResourceType = "volume", Tags = tags)
    )
  )
  if (identical(atlas_ec2_market(market), "on-demand")) request$InstanceMarketOptions <- NULL
  request
}

#' Which of the given AWS error codes an error carries, or NA.
atlas_ec2_error_code <- function(error, codes = ATLAS_EC2_RETRY_ERRORS) {
  text <- conditionMessage(error)
  hit <- codes[vapply(codes, function(code) grepl(paste0("\\b", code, "\\b"), text), logical(1))]
  if (length(hit)) hit[[1]] else NA_character_
}

#' Launch one worker for one shard, trying each instance type in each subnet
#' while capacity refuses (spot, or on-demand with market = "on-demand"). Returns the instance id, or NULL when every
#' option refused for a reason worth retrying later. Any other error stops.
#'
#' Each attempt starts one type further down the list: a worker taken back
#' was taken because its type ran short, so its replacement asks first for
#' a type that has not.
atlas_launch_worker <- function(ec2, config, job_id, shard, grid, attempt = 1L,
                                minutes = config$max_hours * 60, say = function(...) NULL,
                                command = NULL, market = config$market %||% "spot") {
  refusals <- character()
  types <- config$instance_types
  turn <- (as.integer(attempt) - 1L) %% length(types)
  if (turn) types <- c(types[-seq_len(turn)], types[seq_len(turn)])
  for (instance_type in types) {
    for (subnet in config$subnets) {
      request <- atlas_worker_request(config, job_id, shard, grid, attempt, subnet, instance_type, minutes,
                                      command = command, market = market)
      result <- tryCatch(do.call(ec2$run_instances, request), error = function(e) e)
      if (!inherits(result, "error")) return(result$Instances[[1]]$InstanceId)
      code <- atlas_ec2_error_code(result)
      if (is.na(code)) stop(result)
      refusals <- c(refusals, paste0(instance_type, " in ", subnet, ": ", code))
      # A quota applies to every type and zone alike: no point trying them.
      if (!code %in% ATLAS_EC2_CAPACITY_ERRORS) {
        say("shard ", shard, ": launch refused (", code, "); will try again")
        return(NULL)
      }
    }
  }
  say("shard ", shard, ": no ", market, " capacity (", paste(refusals, collapse = "; "), "); will try again")
  NULL
}

#' The job's workers, or, when EC2 fails on its own side (an HTTP 5xx), the
#' error code with no workers: the caller asks again at its next poll. Any
#' other error stops.
atlas_job_instances_unless_down <- function(ec2, job_id) {
  answer <- tryCatch(atlas_job_instances(ec2, job_id), error = function(e) e)
  if (!inherits(answer, "error")) return(list(instances = answer))
  code <- atlas_ec2_error_code(answer, ATLAS_EC2_TRANSIENT_ERRORS)
  if (is.na(code)) stop(answer)
  list(instances = NULL, down = code)
}

#' The workers EC2 knows about for a job: instance, shard, state.
atlas_job_instances <- function(ec2, job_id) {
  rows <- list()
  token <- NULL
  repeat {
    args <- list(Filters = list(list(Name = "tag:atlas-job", Values = list(job_id))))
    if (!is.null(token)) args$NextToken <- token
    response <- do.call(ec2$describe_instances, args)
    for (reservation in response$Reservations) {
      for (instance in reservation$Instances) {
        tags <- stats::setNames(
          vapply(instance$Tags, function(t) t$Value, character(1)),
          vapply(instance$Tags, function(t) t$Key, character(1))
        )
        rows[[length(rows) + 1L]] <- data.frame(
          instance = instance$InstanceId,
          shard = as.integer(tags[["atlas-shard"]]),
          state = instance$State$Name,
          stringsAsFactors = FALSE
        )
      }
    }
    token <- response$NextToken
    if (is.null(token) || !length(token) || !nzchar(token)) break
  }
  if (!length(rows)) {
    return(data.frame(instance = character(), shard = integer(), state = character()))
  }
  do.call(rbind, rows)
}

# States in which an instance will never report again.
ATLAS_EC2_GONE <- c("shutting-down", "terminated", "stopping", "stopped")

#' Whether an image tag exists in its registry, asked anonymously, as a worker
#' will pull it. TRUE, FALSE, or NA when the registry could not be asked.
atlas_image_exists <- function(image) {
  if (!requireNamespace("curl", quietly = TRUE)) return(NA)
  parts <- regmatches(image, regexec("^([^/]+)/(.+):([^:/]+)$", image))[[1]]
  if (length(parts) != 4L) return(NA)
  registry <- parts[[2]]
  repository <- parts[[3]]
  tag <- parts[[4]]
  tryCatch({
    auth <- curl::curl_fetch_memory(
      sprintf("https://%s/token?scope=repository:%s:pull", registry, repository)
    )
    if (auth$status_code != 200) return(NA)
    token <- jsonlite::fromJSON(rawToChar(auth$content))$token
    handle <- curl::new_handle(nobody = TRUE)
    curl::handle_setheaders(handle,
      Authorization = paste("Bearer", token),
      Accept = paste("application/vnd.oci.image.index.v1+json",
                     "application/vnd.oci.image.manifest.v1+json",
                     "application/vnd.docker.distribution.manifest.v2+json", sep = ", "))
    status <- curl::curl_fetch_memory(
      sprintf("https://%s/v2/%s/manifests/%s", registry, repository, tag), handle = handle
    )$status_code
    if (status == 200) TRUE else if (status == 404) FALSE else NA
  }, error = function(e) NA)
}

#' Run a planned job's shards on EC2, relaunching any whose worker disappears,
#' then finish it into a release.
atlas_run_job_on_ec2 <- function(store, job, grid = "draft", ec2 = NULL, config = atlas_ec2_config(),
                                 poll_seconds = 60, wait = Sys.sleep, quiet = FALSE,
                                 clock = Sys.time, image_exists = atlas_image_exists,
                                 finish = TRUE) {
  say <- function(...) if (!isTRUE(quiet)) message(format(clock(), "%H:%M:%S"), "  ", ...)
  # A prior-only job never becomes a release, not even in part at a deadline:
  # once its shards report, one worker builds its private prior instead.
  prior_only <- atlas_is_prior_only(job)
  # A private release (R/hindcast.R) likewise: never published, finished
  # privately on one worker once its shards report.
  private <- atlas_is_private_release(job)
  # A study job (R/studyjob.R): each worker runs one shard of a study
  # command, which publishes its own results; nothing is finished after.
  study <- atlas_is_study_job(job)
  if (prior_only || private || study) finish <- FALSE
  # A full-view refresh is published whole or not at all (R/fullrefresh.R).
  refresh <- atlas_is_full_refresh(job)
  # finish = FALSE runs the shards and stops there: no release is built or
  # promoted (a pilot, run to measure cost; atlas_job_timing reads it).
  # Nothing to fit: only retirements or refreshed public files.
  if (!job$shards) {
    return(if (isTRUE(finish)) atlas_finish_job(store, job$id, grid, quiet = quiet))
  }

  # A worker that cannot pull its image fails every attempt; find out first.
  found <- image_exists(config$image)
  if (identical(found, FALSE)) {
    stop("the image ", config$image, " is not in its registry, so workers could not run it. ",
         "Has CI finished pushing this commit, and is the package public?", call. = FALSE)
  }
  if (is.na(found)) say("could not check that ", config$image, " exists; launching anyway")

  ec2 <- ec2 %||% paws.compute::ec2(config = list(region = config$region))
  deadline <- clock() + config$max_hours * 3600
  minutes_left <- function() as.numeric(difftime(deadline, clock(), units = "mins"))

  latest <- list()
  seen <- character()
  unanswered <- 0L
  attempts <- integer(job$shards)
  # Workers lost in a row without saving anything. A spot worker taken back
  # after saving part of its shard has moved the job on, and its replacement
  # starts from there: only a worker that never gets anywhere uses up tries.
  fruitless <- integer(job$shards)
  saved_at_launch <- integer(job$shards)
  tried_at <- rep(clock(), job$shards)
  launch <- function(shard) {
    tried_at[[shard]] <<- clock()
    id <- atlas_launch_worker(ec2, config, job$id, shard, grid, attempts[[shard]] + 1L,
                              minutes = minutes_left(), say = say,
                              command = if (study) sprintf("run-study --grid=%s --job=%s --shard=%d",
                                                           grid, job$id, as.integer(shard)))
    if (is.null(id)) {
      latest[[as.character(shard)]] <<- NA_character_
      return(invisible(NULL))
    }
    attempts[[shard]] <<- attempts[[shard]] + 1L
    saved_at_launch[[shard]] <<- atlas_shard_saved_count(store, job$id, shard, grid)
    latest[[as.character(shard)]] <<- id
    say("shard ", shard, ": launched ", id,
        if (attempts[[shard]] > 1L) paste0(" (attempt ", attempts[[shard]], ")") else "")
  }
  # EC2 listing the job's workers, asked again (up to tries times) while it
  # fails on its own side; any other error stops.
  listed <- function(tries = 3L) {
    for (i in seq_len(tries)) {
      answer <- atlas_job_instances_unless_down(ec2, job$id)
      if (!is.null(answer$instances)) return(answer$instances)
      if (i == tries) stop("EC2 did not answer (", answer$down, ") to list job ", job$id, "'s workers", call. = FALSE)
      wait(poll_seconds)
    }
  }
  terminate_all <- function() {
    running <- listed()
    running <- running$instance[!running$state %in% ATLAS_EC2_GONE]
    if (length(running)) ec2$terminate_instances(InstanceIds = as.list(running))
    invisible(running)
  }
  shard_done <- function(shard) {
    store$exists(paste0("jobs/", grid, "/", job$id, "/shards/", shard, ".json"))
  }

  # Whatever goes wrong from here on, no worker is left running.
  finished <- FALSE
  on.exit(if (!finished) tryCatch(terminate_all(), error = function(e) {
    message("could not terminate the workers of job ", job$id, ": ", conditionMessage(e),
            "; their shutdown timers will stop them")
  }), add = TRUE)

  # Only the shards that have not reported: run again on a job already part
  # done (after the orchestrator stopped), a reported shard is not fitted a
  # second time, and a study's results are not written twice.
  reported <- atlas_job_status(store, job$id, grid)$done
  if (length(reported)) say(length(reported), " of ", job$shards, " shards already reported; not launched again")
  for (shard in setdiff(seq_len(job$shards), reported)) launch(shard)
  repeat {
    missing <- atlas_job_status(store, job$id, grid)$missing
    if (!length(missing)) break
    if (clock() > deadline) {
      # Stop the workers first, so what they saved holds still, then publish
      # it: the models fitted so far are not thrown away with the job, and
      # the next job plans only what is left.
      terminate_all()
      saved <- sum(vapply(missing, function(n) atlas_shard_saved_count(store, job$id, n, grid), 0L))
      reported <- length(missing) < job$shards
      # Nothing saved and nothing reported: there is nothing to publish.
      partial <- if (isTRUE(finish) && !refresh && (saved || reported)) {
        tryCatch(atlas_finish_job(store, job$id, grid, quiet = quiet, partial = TRUE),
                 error = function(e) e)
      }
      stop("job ", job$id, " ran past its ", config$max_hours, " h deadline with shard",
           if (length(missing) > 1L) "s " else " ", paste(missing, collapse = ", "),
           " unreported; its workers were terminated",
           if (prior_only) {
             "; a prior-only job is never published, in part or whole: plan it again"
           } else if (private) {
             "; a private release is never finished in part: plan it again"
           } else if (study) {
             paste0("; the reported shards' results are under ", job$out)
           } else if (refresh) {
             "; a full-view refresh is never published in part: run it again"
           } else if (is.null(partial)) {
             ", having saved nothing"
           } else if (inherits(partial, "error")) {
             paste0(", and what they saved could not be published: ", conditionMessage(partial))
           } else {
             paste0("; release ", partial$id, " holds every model they saved")
           },
           call. = FALSE)
    }
    answer <- atlas_job_instances_unless_down(ec2, job$id)
    instances <- answer$instances
    if (is.null(instances)) {
      code <- answer$down
      unanswered <- unanswered + 1L
      if (unanswered > ATLAS_EC2_MAX_UNANSWERED) {
        stop("EC2 did not answer for ", unanswered, " polls in a row (", code, "); job ", job$id, " stopped",
             call. = FALSE)
      }
      say("EC2 did not answer (", code, "); asking again at the next poll")
      wait(poll_seconds)
      next
    }
    unanswered <- 0L
    seen <- union(seen, instances$instance)
    for (shard in missing) {
      id <- latest[[as.character(shard)]]
      # Refused last time: try again once a poll has passed, not at once.
      if (is.na(id)) {
        if (clock() > tried_at[[shard]]) launch(shard)
        next
      }
      state <- instances$state[instances$instance == id]
      # EC2 forgets terminated instances after a while: one it has listed
      # before and lists no longer is gone too.
      gone <- if (length(state)) state[[1]] %in% ATLAS_EC2_GONE else id %in% seen
      # A worker writes its record and then shuts down: look again before
      # deciding it died without reporting.
      if (!gone || shard_done(shard)) next
      saved <- atlas_shard_saved_count(store, job$id, shard, grid)
      fruitless[[shard]] <- if (saved > saved_at_launch[[shard]]) 0L else fruitless[[shard]] + 1L
      if (fruitless[[shard]] >= config$max_attempts) {
        stop("shard ", shard, " of job ", job$id, " failed ", fruitless[[shard]],
             " times without reporting or saving anything; its workers were terminated", call. = FALSE)
      }
      say("shard ", shard, ": ", id, " is ", if (length(state)) state[[1]] else "gone",
          " without reporting",
          if (saved) paste0("; ", saved, " of its models are saved, and its next worker starts from there"))
      launch(shard)
    }
    wait(poll_seconds)
  }
  say("all ", job$shards, " shards reported")
  if (prior_only) {
    finished <- TRUE
    terminate_all()
    return(atlas_finish_prior_only_on_ec2(store, job, grid, ec2 = ec2, config = config,
                                          poll_seconds = poll_seconds, wait = wait, quiet = quiet,
                                          clock = clock, image_exists = image_exists))
  }
  if (study) {
    finished <- TRUE
    terminate_all()
    return(invisible(atlas_study_outcome(store, job, grid)))
  }
  if (private) {
    finished <- TRUE
    terminate_all()
    return(atlas_finish_private_release_on_ec2(store, job, grid, ec2 = ec2, config = config,
                                               poll_seconds = poll_seconds, wait = wait, quiet = quiet,
                                               clock = clock, image_exists = image_exists))
  }
  if (!isTRUE(finish)) {
    finished <- TRUE
    terminate_all()
    say("not finished: no release built (--no-finish)")
    return(invisible(NULL))
  }
  if (refresh) {
    finished <- TRUE
    terminate_all()
    # Published only if every refit matches its release, then finished as any
    # release is: that builds the continent export from the new full views.
    release <- atlas_finish_full_refresh(store, job$id, grid, quiet = quiet)
    finished_release <- atlas_finish_on_ec2(store, grid, ec2 = ec2, config = config, poll_seconds = poll_seconds,
                                            wait = wait, quiet = quiet, clock = clock, image_exists = image_exists)
    return(invisible(finished_release %||% release))
  }
  release <- atlas_finish_job(store, job$id, grid, quiet = quiet)
  finished <- TRUE
  terminate_all()
  invisible(release)
}

#' How many shards a job should have: about tasks_per_shard tasks each, and no
#' more workers than allowed.
atlas_shard_count <- function(tasks, max_workers = 4, tasks_per_shard = 40) {
  if (tasks <= 0) return(0L)
  as.integer(max(1, min(max_workers, ceiling(tasks / tasks_per_shard))))
}

#' The whole nightly run on the always-on box: pull, plan, run on EC2, finish.
#'
#' With nothing changed it stops after planning. A job that only retires
#' models or refreshes the public files needs no workers and finishes at once.
atlas_nightly <- function(grid = "draft", algorithms = "all", pull = TRUE,
                          config = atlas_ec2_config(), store = atlas_store(config$store),
                          ec2 = NULL, tasks_per_shard = 40, limit = Inf, quiet = FALSE,
                          pull_occurrences = atlas_pull_occurrences, ...) {
  if (isTRUE(pull)) pull_occurrences(quiet = quiet)
  job <- atlas_plan_job(store, grid, algorithms = algorithms, shards = config$max_workers,
                        tasks_per_shard = tasks_per_shard, limit = limit, quiet = quiet)
  release <- if (!is.null(job)) {
    atlas_run_job_on_ec2(store, job, grid, ec2 = ec2, config = config, quiet = quiet, ...)
  }
  # Then whatever needs every map at once (R/finish.R), even on a night with
  # nothing to fit: a release that was never finished is finished now.
  finished <- atlas_finish_on_ec2(store, grid, ec2 = ec2, config = config, quiet = quiet, ...)
  invisible(finished %||% release)
}
