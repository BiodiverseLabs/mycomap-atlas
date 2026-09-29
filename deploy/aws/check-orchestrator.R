# Ask IAM how it would decide the orchestrator's requests, without making any.
#
#   Rscript deploy/aws/check-orchestrator.R --account=123456789012 --region=us-east-2 \
#     --bucket=mycomap-atlas --security-group=sg-... --profile=atlas-admin
#
# Uses `aws iam simulate-principal-policy`, which launches nothing and changes
# nothing. Every case says what should happen; the script exits non-zero if
# IAM disagrees with any of them. Run it after any change to the policy.
#
# Needs the AWS CLI (ATLAS_AWS_CLI, or `aws` on the PATH) and a profile that
# may call iam:SimulatePrincipalPolicy.

args <- commandArgs(trailingOnly = TRUE)
flag <- function(name, default = "") {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub("^[^=]*=", "", hit[[1]]) else default
}
account <- flag("account")
region <- flag("region")
bucket <- flag("bucket")
group <- flag("security-group")
profile <- flag("profile", "atlas-admin")
aws <- Sys.getenv("ATLAS_AWS_CLI", unset = "aws")
if (!nzchar(account) || !nzchar(region) || !nzchar(bucket) || !nzchar(group)) {
  stop("needs --account, --region, --bucket and --security-group", call. = FALSE)
}

user <- sprintf("arn:aws:iam::%s:user/atlas-orchestrator", account)
ec2 <- function(resource) sprintf("arn:aws:ec2:%s:%s:%s", region, account, resource)
profile_arn <- sprintf("arn:aws:iam::%s:instance-profile/atlas-worker", account)
role_arn <- function(name) sprintf("arn:aws:iam::%s:role/%s", account, name)
image <- sprintf("arn:aws:ec2:%s::image/ami-0123456789abcdef0", region)

context <- function(...) {
  values <- list(...)
  lapply(names(values), function(key) list(
    ContextKeyName = key,
    ContextKeyValues = list(as.character(values[[key]])),
    ContextKeyType = if (is.numeric(values[[key]])) "numeric" else "string"
  ))
}
launch <- function(...) {
  good <- list(`aws:RequestTag/atlas` = "worker", `ec2:InstanceMarketType` = "spot",
               `ec2:MetadataHttpTokens` = "required", `ec2:InstanceProfile` = profile_arn,
               `ec2:InstanceType` = "c7a.8xlarge")
  changes <- list(...)
  for (key in names(changes)) good[[key]] <- changes[[key]]
  do.call(context, Filter(Negate(is.null), good))
}

cases <- list(
  list(TRUE,  "launch a tagged spot c7a.8xlarge worker", "ec2:RunInstances", ec2("instance/*"), launch()),
  list(FALSE, "launch on-demand", "ec2:RunInstances", ec2("instance/*"), launch(`ec2:InstanceMarketType` = "on-demand")),
  list(FALSE, "launch a p5.48xlarge GPU instance", "ec2:RunInstances", ec2("instance/*"), launch(`ec2:InstanceType` = "p5.48xlarge")),
  list(FALSE, "launch without the atlas=worker tag", "ec2:RunInstances", ec2("instance/*"), launch(`aws:RequestTag/atlas` = NULL)),
  list(FALSE, "launch with IMDSv1 allowed", "ec2:RunInstances", ec2("instance/*"), launch(`ec2:MetadataHttpTokens` = "optional")),
  list(FALSE, "launch with another instance profile", "ec2:RunInstances", ec2("instance/*"),
       launch(`ec2:InstanceProfile` = sprintf("arn:aws:iam::%s:instance-profile/other", account))),
  list(TRUE,  "a tagged 60 GB worker disk", "ec2:RunInstances", ec2("volume/*"),
       context(`aws:RequestTag/atlas` = "worker", `ec2:VolumeSize` = 60)),
  list(FALSE, "a 500 GB disk", "ec2:RunInstances", ec2("volume/*"),
       context(`aws:RequestTag/atlas` = "worker", `ec2:VolumeSize` = 500)),
  list(TRUE,  "the worker security group", "ec2:RunInstances", ec2(paste0("security-group/", group)), list()),
  list(FALSE, "any other security group", "ec2:RunInstances", ec2("security-group/sg-00000000000000000"), list()),
  list(TRUE,  "an Amazon-owned image", "ec2:RunInstances", image, context(`ec2:Owner` = "amazon")),
  list(FALSE, "a community image", "ec2:RunInstances", image, context(`ec2:Owner` = "123456789012")),
  list(TRUE,  "terminate an atlas=worker instance", "ec2:TerminateInstances", ec2("instance/i-0123456789abcdef0"),
       context(`aws:ResourceTag/atlas` = "worker")),
  list(FALSE, "terminate any other instance", "ec2:TerminateInstances", ec2("instance/i-0123456789abcdef0"), list()),
  list(FALSE, "tag an instance after launch", "ec2:CreateTags", ec2("instance/i-0123456789abcdef0"),
       context(`ec2:CreateAction` = "CreateTags")),
  list(TRUE,  "pass atlas-worker to EC2", "iam:PassRole", role_arn("atlas-worker"),
       context(`iam:PassedToService` = "ec2.amazonaws.com")),
  list(FALSE, "pass atlas-worker to Lambda", "iam:PassRole", role_arn("atlas-worker"),
       context(`iam:PassedToService` = "lambda.amazonaws.com")),
  list(FALSE, "pass any other role to EC2", "iam:PassRole", role_arn("some-admin-role"),
       context(`iam:PassedToService` = "ec2.amazonaws.com")),
  list(TRUE,  "write to the store", "s3:PutObject", sprintf("arn:aws:s3:::%s/current/draft.json", bucket), list()),
  list(FALSE, "delete from the store", "s3:DeleteObject", sprintf("arn:aws:s3:::%s/current/draft.json", bucket), list()),
  list(FALSE, "read another bucket", "s3:GetObject", "arn:aws:s3:::some-other-bucket/x", list()),
  list(FALSE, "create an IAM user", "iam:CreateUser", sprintf("arn:aws:iam::%s:user/x", account), list()),
  list(FALSE, "create an access key", "iam:CreateAccessKey", user, list())
)

wrong <- 0L
for (case in cases) {
  request <- list(PolicySourceArn = user, ActionNames = list(case[[3]]), ResourceArns = list(case[[4]]))
  if (length(case[[5]])) request$ContextEntries <- case[[5]]
  file <- tempfile(fileext = ".json")
  jsonlite::write_json(request, file, auto_unbox = TRUE)
  out <- suppressWarnings(system2(aws, c("iam", "simulate-principal-policy", "--cli-input-json",
                                         paste0("file://", normalizePath(file, winslash = "/")),
                                         "--profile", profile, "--output", "json"),
                                  stdout = TRUE, stderr = TRUE))
  decision <- tryCatch(jsonlite::fromJSON(paste(out, collapse = "\n"))$EvaluationResults$EvalDecision[[1]],
                       error = function(e) paste("error:", paste(out, collapse = " ")))
  ok <- identical(decision == "allowed", case[[1]])
  if (!ok) wrong <- wrong + 1L
  cat(sprintf("%s  expect %-5s  got %-13s  %s\n", if (ok) "ok " else "BAD",
              if (case[[1]]) "allow" else "deny", decision, case[[2]]))
}
cat(wrong, "case(s) decided differently than intended\n")
quit(save = "no", status = if (wrong) 1L else 0L)
