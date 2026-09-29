# Fill in the AWS policy templates for one deployment.
#
#   Rscript deploy/aws/render.R --account=123456789012 --region=us-east-2 \
#     --bucket=mycomap-atlas --vpc=vpc-... --security-group=sg-... \
#     --subnets=subnet-...,subnet-...,subnet-...
#
# Writes every template under deploy/aws/ to deploy/aws/rendered/ (ignored by
# git), in the same layout. The templates are committed without any account's
# identifiers, so this public repository never carries them and a fork can use
# the same files.
#
# A placeholder is ${NAME}. A placeholder that is a whole JSON string and
# whose value is a list becomes that many strings, which is how one template
# names every subnet.

atlas_render_aws_template <- function(text, values) {
  for (name in names(values)) {
    value <- values[[name]]
    token <- paste0("${", name, "}")
    if (length(value) != 1L) {
      quoted <- paste0("\"", token, "\"")
      text <- gsub(quoted, paste0("\"", value, "\"", collapse = ", "), text, fixed = TRUE)
    }
    text <- gsub(token, value[[1]], text, fixed = TRUE)
  }
  left <- unique(regmatches(text, gregexpr("[$][{][A-Z_]+[}]", text))[[1]])
  if (length(left)) stop("no value for ", paste(left, collapse = ", "), call. = FALSE)
  jsonlite::parse_json(text)
  text
}

atlas_aws_values <- function(account, region, bucket, vpc, security_group, subnets) {
  checks <- list(
    account = "^[0-9]{12}$", region = "^[a-z]{2}-[a-z]+-[0-9]$", bucket = "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$",
    vpc = "^vpc-[0-9a-f]+$", security_group = "^sg-[0-9a-f]+$", subnets = "^subnet-[0-9a-f]+$"
  )
  given <- list(account = account, region = region, bucket = bucket, vpc = vpc,
                security_group = security_group, subnets = subnets)
  for (name in names(checks)) {
    value <- given[[name]]
    if (!length(value) || any(!grepl(checks[[name]], value))) {
      stop("--", gsub("_", "-", name), " is missing or does not look right", call. = FALSE)
    }
  }
  list(
    ACCOUNT_ID = account, REGION = region, BUCKET = bucket, VPC_ID = vpc,
    SECURITY_GROUP_ID = security_group,
    SUBNET_ARNS = sprintf("arn:aws:ec2:%s:%s:subnet/%s", region, account, subnets)
  )
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  flag <- function(name) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit)) sub("^[^=]*=", "", hit[[1]]) else ""
  }
  here <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1]]))
  values <- atlas_aws_values(
    account = flag("account"), region = flag("region"), bucket = flag("bucket"),
    vpc = flag("vpc"), security_group = flag("security-group"),
    subnets = strsplit(flag("subnets"), ",", fixed = TRUE)[[1]]
  )
  out <- file.path(here, "rendered")
  templates <- list.files(here, pattern = "[.]json$", recursive = TRUE)
  templates <- templates[!startsWith(templates, "rendered/")]
  for (template in templates) {
    text <- paste(readLines(file.path(here, template), warn = FALSE), collapse = "\n")
    dest <- file.path(out, template)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    writeLines(atlas_render_aws_template(text, values), dest)
    message("wrote ", dest)
  }
}
