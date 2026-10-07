# Atlas on AWS

Atlas computes on EC2 spot workers and keeps everything in one private S3
bucket. A small always-on box (Lightsail) runs the API, the web app and the
nightly job; it fits nothing itself. This folder holds the IAM and bucket
policies and how to set them up.

```
            nightly (cron on the box)
                     │  atlas-orchestrator (IAM user, keys on the box only)
                     ▼
   ┌─────────── EC2 spot workers ───────────┐
   │ atlas=worker tag, atlas-worker role,    │   no inbound, HTTPS out only
   │ one shard each, then shut down          │
   └───────────────┬────────────────────────┘
                   ▼
        S3 bucket (private, versioned)  ◄──── the box pulls maps and scores
```

## Who may do what

| Identity | May | May not |
|---|---|---|
| **atlas-worker** (instance role; no keys) | list and read the bucket; write `objects/*`, `jobs/*/shards/*`, `jobs/*/logs/*` | write `releases/`, `current/`, `layers/` or a job's plan; delete anything |
| **atlas-orchestrator** (IAM user, the box) | launch spot instances tagged `atlas=worker`, with IMDSv2, the worker's instance profile, an allowed instance type, a disk of at most 200 GB, in the given subnets and security group, from an Amazon image; terminate only `atlas=worker` instances; pass only the worker role, only to EC2; list, read and write the bucket | on-demand or GPU instances, untagged instances, any IAM action, deleting from the bucket, any other bucket |

So a worker cannot change which release is live, and a bug in the
orchestrator cannot start an expensive or unrelated machine: AWS refuses it.

## Files

| File | What |
|---|---|
| `bucket/encryption.json` | default encryption: S3-managed keys, bucket key on |
| `bucket/lifecycle.json` | old object versions expire after 30 days; abandoned uploads after 7 |
| `bucket/policy.json` | refuse any request not made over TLS |
| `worker/trust.json` | only EC2 may assume the worker role |
| `worker/permissions.json` | the worker's bucket access (inline policy `atlas-store`) |
| `orchestrator/permissions.json` | the box's permissions (managed policy `atlas-orchestrator`) |
| `render.R` | fills in the templates for one deployment |
| `check-orchestrator.R` | asks IAM how it would decide 23 requests, allowed and forbidden |

The policy files are **templates**: `${ACCOUNT_ID}`, `${REGION}`, `${BUCKET}`,
`${VPC_ID}`, `${SECURITY_GROUP_ID}` and `${SUBNET_ARNS}` stand for one
deployment's values, so this public repository names no account, network or
bucket. Fill them in first; the result goes to `rendered/`, which git ignores:

```bash
Rscript deploy/aws/render.R --account=<12 digits> --region=us-east-2 \
  --bucket=<bucket> --vpc=<vpc-...> --security-group=<sg-...> \
  --subnets=<subnet-...>,<subnet-...>,<subnet-...>
```

(The security group is created in step 4, so render once without it for steps
2 and 3 — use any `sg-0` placeholder — and again before step 5.)

## Setting it up

Run from an administrator's machine with the AWS CLI, as a profile allowed to
create buckets, IAM roles and users, and security groups. Each step can be
read back before the next. `$P` below is `--profile <admin> --region <region>`
and `$R` the `rendered/` folder as a `file://` path.

**1. The bucket.** Private, public access blocked, encrypted, versioned.

```bash
aws s3api create-bucket --bucket $BUCKET --create-bucket-configuration LocationConstraint=$REGION --object-ownership BucketOwnerEnforced $P
aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true $P
aws s3api put-bucket-encryption --bucket $BUCKET --server-side-encryption-configuration $R/bucket/encryption.json $P
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled $P
aws s3api put-bucket-lifecycle-configuration --bucket $BUCKET --lifecycle-configuration $R/bucket/lifecycle.json $P
aws s3api put-bucket-policy --bucket $BUCKET --policy $R/bucket/policy.json $P
```

Use the bucket's root as the store (`ATLAS_STORE=s3://<bucket>`): the policies
name `objects/`, `jobs/` and the rest at the top of the bucket.

**2. The worker role.**

```bash
aws iam create-role --role-name atlas-worker --assume-role-policy-document $R/worker/trust.json $P
aws iam put-role-policy --role-name atlas-worker --policy-name atlas-store --policy-document $R/worker/permissions.json $P
aws iam create-instance-profile --instance-profile-name atlas-worker $P
aws iam add-role-to-instance-profile --instance-profile-name atlas-worker --role-name atlas-worker $P
```

**3. The worker security group.** No inbound rules; outbound HTTPS only, which
is all a worker needs (package repositories, the container registry, S3).
DNS and the clock use the VPC's own addresses, which security groups do not
filter. Workers need a public address to reach those without a NAT gateway,
which the default VPC's subnets give them.

```bash
SG=$(aws ec2 create-security-group --group-name atlas-worker --description "Atlas spot workers: no inbound, HTTPS out only" --vpc-id $VPC --query GroupId --output text $P)
aws ec2 revoke-security-group-egress --group-id $SG --ip-permissions "IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]" $P
aws ec2 authorize-security-group-egress --group-id $SG --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]" $P
```

The CLI's shorthand splits on commas, so a rule description must not contain one.

**4. The orchestrator.** The policy is longer than the 2,048 characters IAM
allows inline on a user, so it is a managed policy. An account that has never
run a spot instance needs the Spot service-linked role once; it is created
here, by the administrator, so the orchestrator never needs IAM rights.

```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com $P   # once per account
aws iam create-user --user-name atlas-orchestrator $P
aws iam create-policy --policy-name atlas-orchestrator --policy-document $R/orchestrator/permissions.json $P
aws iam attach-user-policy --user-name atlas-orchestrator --policy-arn arn:aws:iam::$ACCOUNT:policy/atlas-orchestrator $P
Rscript deploy/aws/check-orchestrator.R --account=$ACCOUNT --region=$REGION --bucket=$BUCKET --security-group=$SG --profile=<admin>
```

Create the user's access key in the AWS console (IAM → Users →
atlas-orchestrator → Security credentials) and paste it straight into the
box's environment file. It is the box's only secret; it never goes in a
repository, a chat or a worker.

To change a policy later, edit the template, render, and add a version:
`aws iam create-policy-version --policy-arn ... --policy-document ... --set-as-default`
(IAM keeps five; delete the oldest first). Then run the check again.

## The box's settings

The nightly job reads these from the environment:

| Setting | Example | |
|---|---|---|
| `ATLAS_STORE` | `s3://<bucket>` | the store; the bucket's root |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | | atlas-orchestrator's key |
| `AWS_REGION`, `ATLAS_EC2_REGION` | `us-east-2` | |
| `ATLAS_EC2_SUBNETS` | `subnet-…,subnet-…,subnet-…` | one per zone: a launch tries each |
| `ATLAS_EC2_SECURITY_GROUP` | `sg-…` | from step 3 |
| `ATLAS_EC2_INSTANCE_PROFILE` | `atlas-worker` | |
| `ATLAS_EC2_INSTANCE_TYPES` | `c7a.8xlarge,c7i.8xlarge,m7a.8xlarge` | tried in order; must be allowed by the policy |
| `ATLAS_EC2_AMI` | (latest Amazon Linux 2023) | only to pin an image |
| `ATLAS_EC2_MAX_WORKERS` | `4` | shards per job at most |
| `ATLAS_EC2_MAX_HOURS` | `6` | the job's deadline; a worker's shutdown timer is the time left |
| `ATLAS_EC2_MAX_ATTEMPTS` | `3` | launches per shard before the job fails |
| `ATLAS_EC2_VOLUME_GB` | `60` | a worker's disk; the policy allows up to 200 |

Workers run `ghcr.io/biodiverselabs/mycomap-atlas:<commit>`, the image CI
publishes for every commit on main, so they always run the code that planned
their job. The package must be public (workers pull it without credentials).
Before launching anything, the orchestrator checks that the image exists.

## What a job costs, and what stops it

A worker lives until its shard is done, its job's deadline passes, or spot
reclaims it. Three things end it even if the box dies: its own shutdown
timer, set at boot to the time left before the deadline; `InstanceInitiatedShutdownBehavior=terminate`,
so shutting down deletes it and its disk; and the orchestrator, which
terminates every worker of a job when the job fails or finishes.

To see what is running:

```bash
aws ec2 describe-instances --filters Name=tag:atlas,Values=worker Name=instance-state-name,Values=pending,running --query "Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key=='atlas-job']|[0].Value,LaunchTime]" --output table $P
```

A worker's log is uploaded to `jobs/<grid>/<job>/logs/<shard>.log` when it
finishes. There is no SSH into a worker.

## A monthly budget alarm

The limits above stop one job from running away; they say nothing about the
month. An AWS Budgets alarm emails when the account's spend for the calendar
month passes 80% of a limit, and again when AWS forecasts it will pass 100%.
It is AWS's own service, so nothing new is set up outside AWS. The budget
covers the whole account, so it counts the account's other projects too:
set `$LIMIT` to what the account as a whole should cost in a month.

Run from the administrator's machine. Budgets has one endpoint, in
us-east-1, whatever region the account works in; `$ACCOUNT` is the account
number, `$EMAIL` who is told, and `$LIMIT` US dollars (for example `150`).

```bash
aws budgets create-budget --account-id $ACCOUNT --region us-east-1 --profile <admin> \
  --budget "{\"BudgetName\":\"monthly-total\",\"BudgetType\":\"COST\",\"TimeUnit\":\"MONTHLY\",\"BudgetLimit\":{\"Amount\":\"$LIMIT\",\"Unit\":\"USD\"}}" \
  --notifications-with-subscribers "[
    {\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80,\"ThresholdType\":\"PERCENTAGE\"},
     \"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$EMAIL\"}]},
    {\"Notification\":{\"NotificationType\":\"FORECASTED\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":100,\"ThresholdType\":\"PERCENTAGE\"},
     \"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$EMAIL\"}]}]"
```

Read it back, and change the limit later, with:

```bash
aws budgets describe-budget --account-id $ACCOUNT --budget-name monthly-total --region us-east-1 --profile <admin>
aws budgets update-budget --account-id $ACCOUNT --region us-east-1 --profile <admin> \
  --new-budget "{\"BudgetName\":\"monthly-total\",\"BudgetType\":\"COST\",\"TimeUnit\":\"MONTHLY\",\"BudgetLimit\":{\"Amount\":\"$LIMIT\",\"Unit\":\"USD\"}}"
```

Budgets reads the billing data, which lags by up to a day, so it is a
monthly check rather than a brake; the brakes are the policy limits and the
deadlines above. To watch Atlas alone, activate `atlas` as a cost allocation
tag (Billing → Cost allocation tags; workers carry `atlas=worker`) and add a
second budget filtered on the tag value `user:atlas$worker` (quote it in single
quotes in a shell, or `$worker` is expanded).
