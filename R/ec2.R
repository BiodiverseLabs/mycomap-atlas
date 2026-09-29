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
# in deploy/aws/orchestrator/ only allows tagged spot launches of the allowed
# types with the worker's profile, so a bug here fails closed.
#
# The EC2 client is replaceable, which is how the tests run whole jobs — spot
# reclaims and all — without AWS.

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

# Errors that mean "not now": retry at the next poll rather than fail the job.
ATLAS_EC2_RETRY_ERRORS <- c(ATLAS_EC2_CAPACITY_ERRORS, "MaxSpotInstanceCountExceeded",
                            "VcpuLimitExceeded", "RequestLimitExceeded")

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
    image = image,
    max_workers = number("ATLAS_EC2_MAX_WORKERS", 4),
    max_hours = number("ATLAS_EC2_MAX_HOURS", 6),
    max_attempts = number("ATLAS_EC2_MAX_ATTEMPTS", 3),
    volume_gb = number("ATLAS_EC2_VOLUME_GB", 60)
  )
}

#' The script a worker runs at boot. `minutes` is how long it may live: the
#' time left before the job's deadline.
atlas_worker_user_data <- function(job_id, shard, grid, config, minutes = config$max_hours * 60) {
  store <- config$store
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
    "# One fit per ~3 GB of memory, at most one per core.",
    "WORKERS=$(( $(free -g | awk '/^Mem:/{print $2}') / 3 ))",
    "[ \"$WORKERS\" -gt \"$(nproc)\" ] && WORKERS=$(nproc)",
    "[ \"$WORKERS\" -lt 1 ] && WORKERS=1",
    sprintf(paste("docker run --rm -v /data:/data -e ATLAS_STORE=%s -e AWS_REGION=%s",
                  "%s run-shard --grid=%s --job=%s --shard=%d --workers=$WORKERS"),
            shQuote(store), shQuote(config$region), config$image, grid, job_id, as.integer(shard)),
    "STATUS=$?",
    if (grepl("^s3://", store)) {
      sprintf("aws s3 cp /var/log/atlas-worker.log %s/jobs/%s/%s/logs/%d.log || true",
              sub("/$", "", store), grid, job_id, as.integer(shard))
    },
    "echo \"run-shard exited $STATUS\"",
    "shutdown -h now"
  ), collapse = "\n")
}

#' The RunInstances request for one worker in one subnet with one type.
atlas_worker_request <- function(config, job_id, shard, grid, attempt = 1L, subnet, instance_type,
                                 minutes = config$max_hours * 60) {
  tags <- list(
    list(Key = "Name", Value = sprintf("atlas-%s-shard-%d", job_id, as.integer(shard))),
    list(Key = "atlas", Value = "worker"),
    list(Key = "atlas-job", Value = job_id),
    list(Key = "atlas-shard", Value = as.character(shard)),
    list(Key = "atlas-attempt", Value = as.character(attempt))
  )
  user_data <- atlas_worker_user_data(job_id, shard, grid, config, minutes)
  list(
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
}

#' Which of the given AWS error codes an error carries, or NA.
atlas_ec2_error_code <- function(error, codes = ATLAS_EC2_RETRY_ERRORS) {
  text <- conditionMessage(error)
  hit <- codes[vapply(codes, function(code) grepl(paste0("\\b", code, "\\b"), text), logical(1))]
  if (length(hit)) hit[[1]] else NA_character_
}

#' Launch one worker for one shard, trying each instance type in each subnet
#' while spot capacity refuses. Returns the instance id, or NULL when every
#' option refused for a reason worth retrying later. Any other error stops.
atlas_launch_worker <- function(ec2, config, job_id, shard, grid, attempt = 1L,
                                minutes = config$max_hours * 60, say = function(...) NULL) {
  refusals <- character()
  for (instance_type in config$instance_types) {
    for (subnet in config$subnets) {
      request <- atlas_worker_request(config, job_id, shard, grid, attempt, subnet, instance_type, minutes)
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
  say("shard ", shard, ": no spot capacity (", paste(refusals, collapse = "; "), "); will try again")
  NULL
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
                                 clock = Sys.time, image_exists = atlas_image_exists) {
  say <- function(...) if (!isTRUE(quiet)) message(format(clock(), "%H:%M:%S"), "  ", ...)
  # Nothing to fit: only retirements or refreshed public files.
  if (!job$shards) return(atlas_finish_job(store, job$id, grid, quiet = quiet))

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
  attempts <- integer(job$shards)
  tried_at <- rep(clock(), job$shards)
  launch <- function(shard) {
    tried_at[[shard]] <<- clock()
    id <- atlas_launch_worker(ec2, config, job$id, shard, grid, attempts[[shard]] + 1L,
                              minutes = minutes_left(), say = say)
    if (is.null(id)) {
      latest[[as.character(shard)]] <<- NA_character_
      return(invisible(NULL))
    }
    attempts[[shard]] <<- attempts[[shard]] + 1L
    latest[[as.character(shard)]] <<- id
    say("shard ", shard, ": launched ", id,
        if (attempts[[shard]] > 1L) paste0(" (attempt ", attempts[[shard]], ")") else "")
  }
  terminate_all <- function() {
    running <- atlas_job_instances(ec2, job$id)
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

  for (shard in seq_len(job$shards)) launch(shard)
  repeat {
    missing <- atlas_job_status(store, job$id, grid)$missing
    if (!length(missing)) break
    if (clock() > deadline) {
      stop("job ", job$id, " ran past its ", config$max_hours, " h deadline with shard",
           if (length(missing) > 1L) "s " else " ", paste(missing, collapse = ", "),
           " unreported; its workers were terminated", call. = FALSE)
    }
    instances <- atlas_job_instances(ec2, job$id)
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
      if (attempts[[shard]] >= config$max_attempts) {
        stop("shard ", shard, " of job ", job$id, " failed ", attempts[[shard]],
             " times without reporting; its workers were terminated", call. = FALSE)
      }
      say("shard ", shard, ": ", id, " is ", if (length(state)) state[[1]] else "gone",
          " without reporting")
      launch(shard)
    }
    wait(poll_seconds)
  }
  say("all ", job$shards, " shards reported")
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
  if (is.null(job)) return(invisible(NULL))
  atlas_run_job_on_ec2(store, job, grid, ec2 = ec2, config = config, quiet = quiet, ...)
}
