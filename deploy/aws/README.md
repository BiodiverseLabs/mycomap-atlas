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
| `vision-reader/permissions.json` | MycoMap Vision's box: read each release's trained-ids list, nothing else |
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

## A pilot before a full rebuild

A change that makes every model stale (a new null design, a new layer) is
priced with a pilot first: a sample of taxa spread from the richest to the
sparsest, fitted on EC2 like any job, and stopped before a release is built.
On the box, as the atlas user:

```bash
./atlas plan-job --sample=200
./atlas run-job-ec2 --job=<ID from plan-job> --no-finish
./atlas job-timing --job=<ID>
```

`plan-job` says how many models it left for later; the pilot's models plus
those are the full job. `--no-finish` stops once every shard has reported:
nothing is built or promoted, and the release the site serves is untouched.
The pilot's models are refitted by the full job anyway, because the full job
is planned against the current release, not against the pilot.

`job-timing` prints each algorithm's mean and longest seconds per model, the
pilot's own CPU-hours, and the full job's estimate: mean seconds per model
times the full job's models, and that over the fits that run at once (84 by
default: 4 workers of 32 vCPU and 64 GB, one fit per 3 GB; change it with
`--fits-at-once=N` if `ATLAS_EC2_MAX_WORKERS` or the instance types differ).
Set `ATLAS_EC2_MAX_HOURS` to the wall estimate plus half again. A job that
still runs out of time publishes what its shards saved (`finish-job
--partial`) and the next job fits only the rest.

## Which records trained a release (private)

MycoMap Vision benchmarks photo identification on records it holds out,
and weighs photos by Atlas's location prior, so it needs to know which of
its records trained a release's maps. Every finished job writes that list
to the store, beside nothing public:

```
private/trained-ids/<grid>/releases/<release id>.tsv.gz   source, source_id, taxon
private/trained-ids/<grid>/releases/<release id>.json     counts, and any model whose records were not found
private/trained-ids/<grid>/pulls/<sha256>.tsv.gz          each pull's records by taxon and record set (the box's own)
```

A source id (an iNaturalist observation id, say) leads straight to its exact
collection point, so the list is **never** published: not in a release, the
API, the site, Zenodo or the repository. Only presences are listed; the
background sites carry no taxon, so they teach no map a name.

Three ways to get a release's list to Vision's box, from the box as the
atlas user:

- **Its own read access (recommended).** An IAM user or role for Vision's
  box with `vision-reader/permissions.json`: it may list and read
  `private/trained-ids/*/releases/*` and nothing else in the bucket, not
  even the per-pull tables. Vision then fetches the list for whichever
  release its prior came from (`/api/prior` names it), with no step here.
- **A presigned link**, for a one-off: `./atlas trained-ids --link --hours=6`
  prints a link to the current release's list (`--release=ID` for another)
  that works for that long, at most 12 hours, and no longer than the
  signing credentials last.
- **A copy**: `./atlas trained-ids --out=/tmp/trained.tsv.gz`, then copy it
  across yourself. Delete the copy afterwards.

A release made before these lists were kept has none. `./atlas trained-ids
--write` (with `--release=ID` for one that is not current) makes it from the
pull the release's job was planned from, which the store keeps, and the
box's own pull besides; it refits nothing.

## The monthly budget alarm

The limits above stop one job from running away; they say nothing about the
month. The account has one AWS Budgets budget, `My Monthly Cost Budget`: a
monthly cost limit (200 US dollars since 7 October 2026) over the whole
account, so it counts the account's other projects as well as Atlas. It
emails the account's alert address when the month's actual spend passes 85%
and 100% of the limit, and when AWS forecasts the month will pass 100%. It is
AWS's own service, so nothing is set up outside AWS.

Budgets has one endpoint, in us-east-1, whatever region the account works in.
Run these from the administrator's machine; `$ACCOUNT` is the account number.

```bash
aws budgets describe-budget --account-id $ACCOUNT --budget-name "My Monthly Cost Budget" --region us-east-1 --profile <admin>
aws budgets describe-notifications-for-budget --account-id $ACCOUNT --budget-name "My Monthly Cost Budget" --region us-east-1 --profile <admin>
```

**To change the limit**, edit the budget as it stands rather than writing a
new one: `update-budget` replaces the whole budget, so a short one would reset
its cost types and time period. Save it, change `BudgetLimit.Amount`, delete
the read-only `CalculatedSpend`, `LastUpdatedTime` and `HealthStatus` fields,
and send it back:

```bash
aws budgets describe-budget --account-id $ACCOUNT --budget-name "My Monthly Cost Budget" --region us-east-1 --profile <admin> --query Budget > budget.json
aws budgets update-budget --account-id $ACCOUNT --region us-east-1 --profile <admin> --new-budget file://budget.json
```

The alerts and their address are kept when the limit changes. Add another
alert with `create-notification`, or another address with `create-subscriber`.
A new email address must confirm the subscription from AWS's first email
before it is sent anything.

Budgets reads the billing data, which lags by up to a day, so it is a
monthly check rather than a brake; the brakes are the policy limits and the
deadlines above. To watch Atlas alone, activate `atlas` as a cost allocation
tag (Billing → Cost allocation tags; workers carry `atlas=worker`) and add a
second budget filtered on the tag value `user:atlas$worker` (quote it in single
quotes in a shell, or `$worker` is expanded).
