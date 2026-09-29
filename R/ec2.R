# Running a job on EC2.
#
# The always-on box is small (2 GB) and does no fitting. When a plan has work,
# it launches one EC2 spot instance per shard. Each worker boots, installs
# Docker, pulls the release image built from the same commit as the
# orchestrator, runs its shard, uploads its log, and shuts itself down — which
# terminates it. A shutdown timer set at boot does the same if anything hangs,
# so a stuck worker cannot bill for long.
#
# Workers reach the store with an instance role; no keys ever go on an
# instance. Spot capacity can be reclaimed at any moment, so a shard whose
# instance disappears without reporting is launched again, up to a limit. If
# the whole job overruns its deadline, every worker is terminated and the job
# is left unfinished: the next plan picks the same work up, because nothing in
# the current release changed.
#
# The EC2 client is replaceable, which is how the tests run whole jobs — spot
# reclaims and all — without AWS.

ATLAS_EC2_REQUIRED <- c(
  "ATLAS_STORE", "ATLAS_EC2_REGION", "ATLAS_EC2_AMI", "ATLAS_EC2_SUBNET",
  "ATLAS_EC2_SECURITY_GROUP", "ATLAS_EC2_INSTANCE_PROFILE"
)

#' How to launch workers, from the environment. Refuses, naming every missing
#' setting, rather than launching something half-configured.
atlas_ec2_config <- function(env = function(name, unset = "") Sys.getenv(name, unset = unset)) {
  missing <- ATLAS_EC2_REQUIRED[!nzchar(vapply(ATLAS_EC2_REQUIRED, env, character(1)))]
  if (length(missing)) {
    stop("EC2 is not configured; set ", paste(missing, collapse = ", "),
         " (see deploy/aws/README.md)", call. = FALSE)
  }
  commit <- atlas_code_commit()
  number <- function(name, default) {
    value <- suppressWarnings(as.numeric(env(name, as.character(default))))
    if (is.na(value)) stop(name, " must be a number", call. = FALSE)
    value
  }
  list(
    store = env("ATLAS_STORE"),
    region = env("ATLAS_EC2_REGION"),
    ami = env("ATLAS_EC2_AMI"),
    subnet = env("ATLAS_EC2_SUBNET"),
    security_group = env("ATLAS_EC2_SECURITY_GROUP"),
    instance_profile = env("ATLAS_EC2_INSTANCE_PROFILE"),
    instance_type = env("ATLAS_EC2_INSTANCE_TYPE", "c7a.8xlarge"),
    # The image built from the orchestrator's own commit, so workers run
    # exactly the code that planned the job.
    image = env("ATLAS_IMAGE", paste0("ghcr.io/biodiverselabs/mycomap-atlas:", commit)),
    max_workers = number("ATLAS_EC2_MAX_WORKERS", 4),
    max_hours = number("ATLAS_EC2_MAX_HOURS", 6),
    max_attempts = number("ATLAS_EC2_MAX_ATTEMPTS", 3),
    volume_gb = number("ATLAS_EC2_VOLUME_GB", 60)
  )
}

#' The script a worker runs at boot.
atlas_worker_user_data <- function(job_id, shard, grid, config) {
  store <- config$store
  paste(c(
    "#!/bin/bash",
    "# MycoMap Atlas worker. Runs one shard of a job, then shuts down (which",
    "# terminates this instance).",
    "set -uxo pipefail",
    sprintf("shutdown -h +%d  # the deadline: a hung worker stops billing", as.integer(config$max_hours * 60)),
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

#' Launch one worker for one shard. Returns its instance id.
atlas_launch_worker <- function(ec2, config, job_id, shard, grid, attempt = 1L) {
  tags <- list(
    list(Key = "Name", Value = sprintf("atlas-%s-shard-%d", job_id, as.integer(shard))),
    list(Key = "atlas", Value = "worker"),
    list(Key = "atlas-job", Value = job_id),
    list(Key = "atlas-shard", Value = as.character(shard)),
    list(Key = "atlas-attempt", Value = as.character(attempt))
  )
  user_data <- atlas_worker_user_data(job_id, shard, grid, config)
  result <- ec2$run_instances(
    ImageId = config$ami,
    InstanceType = config$instance_type,
    MinCount = 1, MaxCount = 1,
    SubnetId = config$subnet,
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
  result$Instances[[1]]$InstanceId
}

#' The workers EC2 knows about for a job: instance, shard, state.
atlas_job_instances <- function(ec2, job_id) {
  response <- ec2$describe_instances(Filters = list(
    list(Name = "tag:atlas-job", Values = list(job_id))
  ))
  rows <- list()
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
  if (!length(rows)) {
    return(data.frame(instance = character(), shard = integer(), state = character()))
  }
  do.call(rbind, rows)
}

# States in which an instance will never report again.
ATLAS_EC2_GONE <- c("shutting-down", "terminated", "stopping", "stopped")

#' Run a planned job's shards on EC2, relaunching any whose worker disappears,
#' then finish it into a release.
atlas_run_job_on_ec2 <- function(store, job, grid = "draft", ec2 = NULL, config = atlas_ec2_config(),
                                 poll_seconds = 60, wait = Sys.sleep, quiet = FALSE,
                                 clock = Sys.time) {
  say <- function(...) if (!isTRUE(quiet)) message(format(clock(), "%H:%M:%S"), "  ", ...)
  ec2 <- ec2 %||% paws.compute::ec2(config = list(region = config$region))
  deadline <- clock() + config$max_hours * 3600

  latest <- list()
  attempts <- integer(job$shards)
  launch <- function(shard) {
    attempts[[shard]] <<- attempts[[shard]] + 1L
    latest[[as.character(shard)]] <<- atlas_launch_worker(ec2, config, job$id, shard, grid, attempts[[shard]])
    say("shard ", shard, ": launched ", latest[[as.character(shard)]],
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

  for (shard in seq_len(job$shards)) launch(shard)
  repeat {
    missing <- atlas_job_status(store, job$id, grid)$missing
    if (!length(missing)) break
    if (clock() > deadline) {
      terminate_all()
      stop("job ", job$id, " ran past its ", config$max_hours, " h deadline with shard",
           if (length(missing) > 1L) "s " else " ", paste(missing, collapse = ", "),
           " unreported; its workers were terminated", call. = FALSE)
    }
    instances <- atlas_job_instances(ec2, job$id)
    for (shard in missing) {
      id <- latest[[as.character(shard)]]
      state <- instances$state[instances$instance == id]
      gone <- length(state) == 1L && state %in% ATLAS_EC2_GONE
      # A worker writes its record and then shuts down: look again before
      # deciding it died without reporting.
      if (!gone || shard_done(shard)) next
      if (attempts[[shard]] >= config$max_attempts) {
        terminate_all()
        stop("shard ", shard, " of job ", job$id, " failed ", attempts[[shard]],
             " times without reporting; its workers were terminated", call. = FALSE)
      }
      say("shard ", shard, ": ", id, " is ", state, " without reporting")
      launch(shard)
    }
    wait(poll_seconds)
  }
  say("all ", job$shards, " shards reported")
  release <- atlas_finish_job(store, job$id, grid, quiet = quiet)
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
                          ec2 = NULL, tasks_per_shard = 40, quiet = FALSE, ...) {
  if (isTRUE(pull)) atlas_pull_occurrences(quiet = quiet)
  job <- atlas_plan_job(store, grid, algorithms = algorithms, shards = config$max_workers,
                        tasks_per_shard = tasks_per_shard, quiet = quiet)
  if (is.null(job)) return(invisible(NULL))
  if (!job$shards) return(atlas_finish_job(store, job$id, grid, quiet = quiet))
  atlas_run_job_on_ec2(store, job, grid, ec2 = ec2, config = config, quiet = quiet, ...)
}
