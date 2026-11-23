# Note on resuming seed 2 of the stricter null test for maps with 200+ sites

Written on 2026-11-23 by the method lane. No seed-2 verdict, score, p,
pass count, pass rate or per-species time had been seen by the method lane
when it was written, and none had been reported to it by anyone. "What has
been read, and when" says what was opened, and how. It adds to two entries
and changes neither:
- the pre-registration docs/experiments/2026-11-22-large-taxon-rule-seed2.md,
  sha256 LF 0971ad50e4e6500c8d7c66cd080a1d92a82cb9bac07f1ec8058d67fb6bccc311;
- its addendum docs/experiments/2026-11-23-large-taxon-rule-seed2-addendum.md,
  sha256 LF cb60102d1d6e58e36067d48956afdac8631cf13de6f9aecd47dcbe69f77a9029.

Counts and times only.

## What happened

- **The run:** study job study-20261123T081504Z-6e41f5ca. It ran from 08:15
  to 13:15:34 UTC (03:15 to 08:15 EST) on 2026-11-23 and stopped with exit
  1: "ran past its 5 h deadline with shards 1–8 unreported; workers
  terminated". The shards' saved progress was kept, and every worker was
  terminated. The 08:15 launch counts as the first attempt.
- **Spot reclaims:**
  - All 8 first workers were lost within 4 to 9 minutes.
  - Later workers were lost on shards 1, 3, 4, 5 and 8.
  - After that, no spot capacity was available.
  - Shards 2, 6 and 7 each ran on one worker for nearly 5 hours and did not
    finish.
- **Species saved per shard when the run stopped**, out of 175 each:
  - saved: 173, 173, 170, 169, 171, 174, 174, 174 (shards 1 to 8), 1,378 in
    all;
  - unsaved: 22, all at 200+ sites, 19 habitat and 3 geography;
  - unsaved per shard: shards 1 and 2, 2 habitat each; shard 3, 4 habitat
    and 1 geography; shard 4, 5 and 1; shard 5, 3 and 1; shards 6, 7 and 8,
    1 habitat each.
- **Instance type of every attempt so far**, from the worker logs:
  - attempt 1 of shards 1, 2, 3, 5, 7 and 8 ran on r7i.8xlarge;
  - every later attempt with a log, 13 of them, ran on m7i.8xlarge;
  - shards 4 and 6 left no attempt-1 log, because those workers were lost
    before their first 5-minute log upload.

  Both types are 4th-generation Xeon (Sapphire Rapids). Most saved rows were
  scored on m7i.8xlarge.
- **Spend so far:** about 40 instance-hours, about $25-35 at the spot prices
  seen ($0.49-0.88/h) (ops, 2026-11-23). The billed figure is not available
  until 2026-11-24.

**Why the deadline was too short.** Each shard holds 175 species in the same
mix:
- 80 geography species below 200 sites;
- 30 habitat species at 200+;
- 20 geography species at 200+;
- 45 ESM geography species.

They are dispatched in layout order, band by band (R/study.R:241,
R/batch.R:237). The 30 habitat species at 200+ have a real signal, so their
tests seldom reach 3 nulls as good. Most draw all 199 nulls on 5 splits. On
seed 1's cost per null at 200+ (Maxent 45 s, random forest 7.7 s), each is
at least about 2.9 hours of one process. Seed 1's figures are wall-clock
times, and its long tests borrowed idle cores late in a shard, so the
one-process cost is higher. Together these species hold the shard's 30
processes for hours while the cheaper species wait behind them. Seed 1 had
no habitat species, so its times did not show this. Shards 2, 6 and 7 ran
for 4.9 hours without a break and still had 1 or 2 habitat species
unsaved.

## What has been read, and when

Times are UTC on 2026-11-23, in the order things happened.

- **13:15:34:** the job stopped at its deadline.
- **Before 13:35:** the method lane answered the coordinator's questions
  from the code and seed 1's already-registered files only. The proposal to
  resume, and the stopping rule (one resumed attempt, read once when it
  ends), were part of those answers.
- **13:35 and 13:36:** reader v3 and draft 1 of this note were written and
  hashed.
- **13:38:** draft 2 was hashed. It adds that a launch with nothing in the
  store is not the attempt.
- **14:33:** ops' copy of the run's files reached the method lane, in
  calibration/run-20261123/job/: job.json, 19 worker logs, and the 8
  shards' progress .json and .rds files.
- **14:35:** the method lane read all 19 logs and all 8 progress .json files
  with one script, calibration/blind_digest_seed2.py (sha256
  0ac59022c7fc29b2891bfcbbfd0ce63e1c9db7484bc58fefbc2d3d9568d3e5ad). The
  script read each file in memory and printed only:
  - per log: the line count, the species rows by status (every one
    "scored"), the times of the first and last species row, and the longest
    gap between rows;
  - every line that is not a species row (boot, docker, instance type, the
    study's opening line, the "already scored" line, exit status), with
    every digit replaced and the words passed, failed and untested masked;
  - per progress file: row count, distinct species, status counts, species
    from another shard (0), and the unsaved species by kind and band.
- **By hand, outside the script, after 14:35:**
  - a search of the raw logs for instance-type, exit-status, error, kill
    and memory lines, with species rows left out of the search;
  - the time of each log's last species row (its first 8 characters only);
  - the first 60 characters of each log's last line, an upload command.
- **What is kept of it:** the script's masked output was saved as a
  tool-results file on the method lane's machine, which keeps what was
  shown. The method lane has not opened it since.
- **Later, a hash check:** the method lane ran sha256sum -c against ops' list
  of the 36 files (seed2-attempt1-files.sha256, below). That reads each
  file's bytes to hash them and shows nothing of their content.
- **14:50 to 17:52: Steve set the conditions** of the resumed attempt
  (below). The answers were given in three sessions, which crossed. Every
  answer is listed here, in order of time. All came after the 14:35 digest,
  so he knew the 22's kinds and bands throughout.
  1. **Shortly before 14:53**, in the method lane's session: r7i.2xlarge, a
     20-hour cap after the 11/24 nightly, about $85.
  2. **14:52:50**, in the coordinator's session: "Mid machine, 16 h"
     (r7i.4xlarge, a 16-hour cap, $140). The worst-case estimate in front of
     him then was about 14 hours. The reason given for r7i.4xlarge was that
     no species would share a physical core.
  3. **About 14:54**, in the method lane's session, with answers 1 and 2
     side by side: r7i.4xlarge, 16 hours, $140.
  4. **Between 14:53 and 14:57**, twice, to ops. Once, "Launch; trim cap if
     late (Rec.)" on r7i.2xlarge with 20 hours. Then, with both sizes and
     the physical-core point put to him (ops recommended r7i.4xlarge):
     "2xlarge, 20 h". The exact times are with ops.
  5. **14:57:01**, in the coordinator's session, to a question that named
     the conflict between the three sessions and gave three options (small
     machine 20 h, mid 16 h, mid 20 h) with their memory and cap
     trade-offs: "Small, 20 h" (r7i.2xlarge, 20 hours with the trim rule,
     ceiling $84.67). **This is the decision.**
  6. **About 17:52**, in the method lane's session, asked once more which
     answer stood, with both versions in front of him: "r7i.2xlarge, 20 h".
     This confirms answer 5.

  **Why it moved.** It moved from 16 to 20 hours on two grounds:
  - the method lane's later one-process figures, which put a 199-null test
    at 10.6 hours and the bounded worst case at 21.2 hours, both at the
    upper cost per table and above the earlier estimate of about 14 hours;
  - the box's limit of no run beside a nightly.

  Then came a deliberate final choice, made with both machine sizes, the
  physical-core point and the memory margin in front of him. The method
  lane's figures also show that the core-sharing concern is already inside
  the basis (below).

**Never shown, and nothing computed from them:**
- any species row of a log;
- any verdict, rho, AUC, p, Boyce index or pass count;
- any per-species time.

The script and the search patterns dropped these before anything was shown.
job.json and the .rds files were not opened. No reader has been run on the
folder, and the copies count below has not been run.

**What was shown that may hint at outcomes, stated openly:**
- the unsaved species' kinds and bands;
- per log, the times of row completion and the longest gap between rows.

A species still running at the stop is likelier to be one that drew many
nulls. At 200+ sites, a test that draws many nulls is one that has not yet
had 3 nulls as good as the map. So the unsaved species lean towards maps
that do well against their nulls. The method lane, the coordinator, ops and
Steve all knew this before the conditions were set.

The resume was forced by the deadline, and its stopping rule was written at
13:36, before any of this was known at 14:35. The conditions set later
decide only the market, the machine and the hours. They change no species,
setting or rule, and whatever they cover is scored as it comes. Anything
left unscored is counted both ways. From 14:35 until the resumed attempt
ends, nothing more in that folder is opened.

## The resume

- **What stays the same:** the same study job, study-20261123T081504Z-6e41f5ca;
  the same commit (feat/large-taxon-nulls
  d04c60a7aa2772ad98354a69f8bb9c2526e92b60); the same image
  (`:study-d04c60a7aa2772ad98354a69f8bb9c2526e92b60`); the same command and
  arguments (`study-calibration --seed=2 --workers=30 --null-rule=production
  --designs=shift --effort-arms=none --bands=habitat:200+`); and the same
  1,400 species.
- **Saved species:** each shard keeps the species its earlier attempts
  saved, and scores only the others. The others include species that were
  running when a worker was lost, and species that finished after the
  shard's last upload, which happens every 5 minutes (R/ec2.R:155). Each of
  these is scored again from its start.
- **The launcher can resume this job with no code change** (ops,
  2026-11-23). atlas_run_job_on_ec2 sets a fresh deadline from its own start
  (R/ec2.R:423) and resets its attempt counters. It relaunches every
  unreported shard, whose worker then starts from that shard's progress.rds.

**Why a resumed run gives the rows an unbroken run would.** All file and line
references are at d04c60a7.
- Each species is seeded from its own fingerprint: seed 2 and its name
  (R/studycalibration.R:490, :255). Its null draws are seeded from that seed
  plus 1000 plus the draw, and its null fits from that seed plus 2000 plus
  the draw (R/nulls.R:335, :347). Nothing in a species' result depends on
  the other species, on the time, or on the attempt.
- The test's result is the same however many processes score its nulls, and
  whatever the batch size. This is tested for every learner in
  tests/testthat/test-nulls.R:597, and with real forks inside a pool's
  process at :624.
- A resumed shard keeps saved rows only when the job, shard, study and
  settings are identical (R/study.R:179-182). It retries any saved row that
  failed. Tested in tests/testthat/test-studyresume.R:44, which ends with an
  unbroken run's rows, and :76.
- **All of this holds on the same microarchitecture.** The fits run
  single-threaded BLAS, whose kernels are chosen per CPU.
  - The saved rows come from r7i.8xlarge and, mostly, m7i.8xlarge, both
    Sapphire Rapids. The remainder runs on r7i.2xlarge, also Sapphire
    Rapids.
  - Each species is always computed whole on one machine.
  - About 150 species were scored in the lost first attempts on r7i.8xlarge
    and again on m7i.8xlarge. Their logs hold both copies, so the reader's
    "copies that disagree" count tests this claim directly. That count runs
    once, with the read.

## Conditions of the resumed attempt

Set by Steve on 2026-11-23. The final answer was given at 14:57:01 UTC and
confirmed at about 17:52 UTC (see the timeline).

| | |
|---|---|
| Market | On demand |
| Instance type, pinned | r7i.2xlarge only, 8 workers |
| Image and arguments | Unchanged: no new image |
| Hours cap (enforced) | 20 h, set once at launch by the trim rule below. The launcher enforces hours only: each worker's shutdown timer counts from its boot (R/ec2.R:157-171), and the job deadline from the orchestrator's start (R/ec2.R:423). |
| Trim rule | If the 11/24 nightly ends after 11:00 UTC, ops lowers MAX_HOURS so that the run ends by 06:45 UTC on 11/25, but never below 18 h. Below 18 h, ops holds and asks Steve. The cap is therefore 18 to 20 h. It depends only on the clock time at which the nightly ends, and on nothing seen in the run. |
| Dollar figure | $84.67: an arithmetic ceiling, 8 workers × 20 h × $0.5292/h (AWS Pricing API, us-east-2, on demand; ops). The launcher has no dollar cap. Each worker stops when its shard ends, so the expected cost is about $17-30. |
| When | Ops launches on Steve's go: after this note is committed, after the 11/24 nightly has ended, and never alongside a nightly. The box does not run two orchestrators at once. |
| Launch script | /srv/atlas/calib-20261123/resume.sh on the box, sha256 b87256a52388b7e00309463eeda880acd4b4a3449c5be4b5fa3567855d76240a. The coordinator read it and diffed it against run.sh (270412a0…). It changes the market (spot to on demand), MAX_HOURS (5 to 20), the instance types (r7i.8xlarge,m7i.8xlarge to r7i.2xlarge) and the container name, and it fixes the job id in the script. With those removed, the rest of the docker command is identical. The image tag is study-d04c60a7aa2772ad98354a69f8bb9c2526e92b60. A trimmed cap changes MAX_HOURS only, and ops records the hash of the script as launched. |
| Can this job id be resumed? | Yes, with no code change (ops). |
| Is the type allowed? | Yes. The type is a launcher setting only (ATLAS_EC2_INSTANCE_TYPES), and the live orchestrator policy allows r7i.* on demand. Ops confirmed r7i.2xlarge by name. |
| Quota | On-demand quota 256 vCPU. This attempt uses 64 (8 × 8). The nightly's shards use the separate spot quota (ops). |
| Termination | Per job (tag:atlas-job), so neither job's deadline touches the other's workers (ops). |

**The basis.** A resumed shard starts one process per species it has left:
min(30, species left) (R/study.R:121). A model borrows only idle processes of
its own pool, where idle means pool size less busy (R/batch.R:183,
R/nulls.R:488). With 1 to 6 species left, every process is busy, so each of
the 22 runs on one process. A shard takes as long as its slowest remaining
species.

**The one-process cost per null table.** A table is the map or one null,
each scored on 5 splits. The figures come from seed 1's run of 2026-11-21
(production's 5-split test, r7i.8xlarge, 30 processes), at 200+ sites:
- **Lower figure:** wall seconds per table in tests that drew 99 nulls or
  more: Maxent 18-42 s, random forest 2-6 s. These tests ran partly with
  borrowed cores late in a shard, so one process costs more.
- **Best estimate:** arm seconds ÷ tables over all tests, which mostly ran
  mid-shard on one process: Maxent median 75 s, random forest median 17 s.
  Over all tables pooled, Maxent 45 s and random forest 7.7 s. These figures
  include each arm's own fit and scoring, so they overstate the cost a
  little. Best estimate: Maxent 60 s and random forest 12 s.
- **Upper figure:** the 90th percentile of the same ratio, Maxent 162 s and
  random forest 29 s. The highest seen were 256 s and 41 s.

**Core sharing on r7i.2xlarge.** r7i.2xlarge has 8 vCPUs on 4 physical
cores. Shards 3 and 4, with 5 and 6 species, put up to 1.5 processes on a
physical core; shard 5, with 4 species, puts one on each. Seed 1's figures
were measured at about 1.9 processes per physical core (30 on 16). So they
already carry more sharing than any resumed shard will have, and the hours
below hold for shards 3 and 4 as they stand. A shard's sharing also falls as
its species finish.

**One species on one process**, the map plus its nulls, Maxent then random
forest:

| | Best estimate | Upper figure | Highest seen |
|---|---|---|---|
| Usual long test: 199 nulls (200 tables) | 200 × 72 s = 4.0 h | 200 × 191 s = 10.6 h | 200 × 297 s = 16.5 h |
| Bounded worst case: 398 nulls (399 tables) | 399 × 72 s = 8.0 h | 399 × 191 s = 21.2 h | 399 × 297 s = 32.9 h |

**No species can run without end:**
- the null sequence draws at most 2 × 199 = 398 null tables (R/nulls.R,
  atlas_null_sequence);
- the species' own draw is redrawn at most 20 times, which adds minutes,
  since it places points and fits nothing;
- every fit has fixed iteration and tree counts.

**What the cap covers**, at 20 h (and at the 18 h floor):
- the usual 199-null test at the upper figure (10.6 h), with margin;
- 1.2 times the nulls at the upper figure (about 240 tables, 12.7 h), which
  is the most any of seed 1's 200+ tests drew;
- the usual test at the highest cost seen (16.5 h);
- the bounded worst case at the best estimate (8.0 h);
- about 375 of the 399 worst-case tables at the upper figure (about 340 at
  18 h).

It does not quite cover the bounded worst case at the upper figure (21.2 h).
A species that reaches the cap is left unscored and counted both ways under
the stopping rule.

**Cost, on demand**, as considered. Prices are AWS's us-east-2 Linux
on-demand rates:

| Type | vCPU / physical cores / memory | Price | 8 shards at about 4-7 h | Ceiling at 20 h |
|---|---|---|---|---|
| **r7i.2xlarge (chosen)** | 8 / 4 / 64 GiB | $0.5292/h | about $17-30 | $84.67 |
| r7i.4xlarge | 16 / 8 / 128 GiB | about $1.06/h | about $34-59 | about $169 |
| r7i.8xlarge | 32 / 16 / 256 GiB | about $2.12/h | about $68-119 | about $339 |

**Why the machine changes no number:**
- The pool is min(30, species left) (R/study.R:121). That is at most 6 here,
  whatever the machine.
- The study passes --workers=30 itself. It does not use the worker script's
  memory-based WORKERS setting, which run-shard jobs use (R/ec2.R:162,
  :193-195).
- Each process runs single-threaded BLAS.
- r7i.2xlarge is the same Sapphire Rapids microarchitecture.
- Nothing in the study reads the machine's core count:
  - parallel::detectCores() is used only for fetch and export process counts
    (R/jobs.R:101, R/parallel.R:67), which a study does not use;
  - it is also used for the machine record a shard writes (R/jobs.R:767),
    which notes the machine and changes no result.

**Memory: 6 one-process species at 200+ on 64 GiB.**
- Workers have no swap, and the study container has no memory limit, so
  what counts is the instance's RAM less the system and docker (ops).
- The highest measured peak is in the code: a widespread taxon's Maxent fit
  with its background at the 10,000-site cap peaked at 8.9 GB while tuning
  (R/ec2.R:141-147, 2026-10-13). Seed 2's 200+ species are drawn with the
  same 10,000-site cap.
- Six such peaks at once would be about 53 GB. 64 GiB is about 68.7 GB, so
  about 14 GB is left after the system's share.
- Peaks are passing moments in tuning, so six at the same instant is the
  worst case, not the usual load.
- A resumed shard makes no forks, because no process is idle.
- Today, 30 processes and their forks ran on the 128 GiB m7i.8xlarge with no
  out-of-memory kill in any log.
- Only shard 4 has 6 species. Every other shard has 5 or fewer.

The method lane judges this margin sound.

**If memory runs out anyway**, the stopping rule decides:
- **If the kernel kills one pool process:** the shard's pool loses its
  connection. Every species still running or unsent in that shard is then
  recorded as failed ("worker lost") (R/batch.R:249-265). On a resumed
  shard, that means all of its remaining species, not just one. The shard
  saves and publishes its rows and reports. Its failed share is at most
  6 of 175, under the 5% limit (R/study.R:215, :221-231). So the launcher
  does not relaunch it, and those species stay failed. At the read, a
  failed row is unscored and counted both ways.
- **If the whole container dies** (exit 137): the worker reports nothing,
  and the launcher relaunches the shard as a new worker. It does so up to 3
  times without new saves (ATLAS_EC2_MAX_ATTEMPTS, R/ec2.R:136, :557). That
  worker retries the failed rows. On demand there are no reclaims, so a 137
  would mean memory or the deadline. That relaunch is part of the one
  attempt.

**Market:** on demand. A species saves nothing partway through, so a spot
reclaim would throw away hours of work. The market changes only that risk,
never a result.

## Considered and not chosen: a new image

A new image in which a resumed shard's pool keeps idle processes, so each
remaining species borrows up to 8 cores, would take each shard to about 1 to
1.5 hours. Results would not change: process count does not change a result
(tests/testthat/test-nulls.R:597, :624). But it would change the registered
image after an outcome-blind look at a part-finished run, and it would need
its own review, a Linux-green run, a build and a note. Steve chose no new
image.

## The stopping rule

- **One resumed attempt.** One attempt means one launch of run-job by ops,
  under one deadline. While it runs, the launcher may relaunch a shard by
  itself, for any reason: a reclaimed or lost worker, or a container that
  exited without reporting, as after an exit 137. Every such automatic
  relaunch within the job is part of the one attempt. Nobody launches
  anything else by hand.
- **A launch that never started scoring is not the attempt.** Examples are
  an expired AWS sign-in, a capacity refusal for every shard at launch, or a
  launcher error. The test is what the store holds from that launch:
  - no worker log of the launch holds its study opening line ("175 virtual
    species (shard i/8, seed 2)…"), which a worker writes before it tries any
    species; and
  - no shard saved a species during it.

  A worker's log reaches the store every 5 minutes (R/ec2.R:187-190). A
  worker lost sooner may have written the line without it arriving. Nothing
  from that worker is in the store, so nothing can have been seen.

  Such a launch carries no outcome, and ops may launch again under the same
  conditions. Once any worker log of a launch in the store holds that line,
  or any shard has saved a species during it, that launch is the attempt,
  however it ends and however few species it scored. Ops records every
  launch: its start, its end, and whether either of those was in the store.
  Its spend is reported with the run's.
- **Read once, when the attempt ends**, whether it is complete or not.
- **Anything left unscored** is counted both ways, as registered, against the
  full 1,400-species layout. That includes a species left as a failed row.
  The reader is read_seed2_v3.py (below).
- **No relaunch** is decided on anything seen, and nobody reads a checkpoint
  before the attempt ends. While it runs, ops reports only the count of
  saved species per shard, by kind and band, which carries no outcome.

## What ops hands over

- Every attempt's worker logs, from the first launch on 2026-11-23 to the
  end of the resumed attempt.
- Every shard's progress files.
- The final results files.
- Worker times, instance types, and the spend.
- The hash of the launch script as launched.

**A resume overwrites the store's worker logs.** run-job-ec2 counts attempts
from 1 again at each launch (R/ec2.R:429), and logs are named
<shard>-<attempt>.log (R/ec2.R:165). So the resumed attempt's logs replace
the store's copies of today's logs. Ops keeps its copies, in
calibration/run-20261123/job/. These copies are the only record of today's
attempts, and the copies count needs them.

Ops has hashed them: calibration/run-20261123/seed2-attempt1-files.sha256,
36 lines, sha256 3cb919b4e2fab403028945d4e580aed98a4b92d8353d2af9ee99fe6606c9da1c.
- It covers the 19 logs, the 8 shards' progress .json and .rds, and
  job.json. Ops checked them size-identical to the store.
- The method lane checked every one of the 36 against the list (all OK).
- The 19 log hashes, from that list, are below. For the progress files and
  job.json, the list's own hash above stands.

| Log | sha256 |
|---|---|
| logs/1-1.log | 58e9fab94bf1a6885a0757f3d89540d8150b97a3d914cac3e99356e69e767de6 |
| logs/1-2.log | 60aa13ace7f18128cd902585f832656f7fe7ae3f8448fde150937aed612d50a8 |
| logs/1-3.log | f08484a69193b74dacdcd7170a45d23f82e21378182cf720b3629b5d3bc215a1 |
| logs/2-1.log | 75c33431f201efa56e450bce77c0c9fcae4522ebd4737039024150b76f442736 |
| logs/2-2.log | 6bf4b8c8614ab858d060393a5175449100c76bcdabe32338323e491c9f7cf8e4 |
| logs/3-1.log | f27d619dd83b06f081e4a02982f9a01d0d7fd0675c24d1d4587f05d5614d479e |
| logs/3-2.log | 799a7253472037cca160cdb6b1137e6f4ed34b66263fd79baddfc50b35c9ee07 |
| logs/3-3.log | c01373961257876b8108b312c67facd94151a1cbadb180ee3c5922697b011cd0 |
| logs/4-2.log | 28ade5e4b05b5c0c4dd760ac8e532e08b179700aa7951e1fcfd7ef6275d31b3f |
| logs/4-3.log | 18b826382790cc3db8f504f07c9228023fa93ba5a12e1e2276acace1dd860a0b |
| logs/5-1.log | 105c592273c1736cad3a43e94fd489b342611e8ef16e7e8af846e8ec44a5586a |
| logs/5-2.log | 19b26d8eac951ef61b5e05d71c6d48c5493ca39543e8c6ea1e496a04c192db08 |
| logs/5-3.log | 8845b6f661330314322705e9c72be095148dd4dd605c2607ea3d050820df9fb2 |
| logs/6-2.log | 7945b6678655e871c5b90b5ee2a1bc89ce389df5382ba352d65507e4c3a4e081 |
| logs/7-1.log | e95d814138118bd8ea2fb8c670b1c33b003c3fa0197f082e0838f3751c7cfb5d |
| logs/7-2.log | 4436beec1fd3eebdd06447d66a70f04f6e7ce1eb50aacea17dcd272b3f9dee5b |
| logs/8-1.log | 4de6b8115153ac70f356b29130aa67e940e4dc6933987684f09f759c8931b104 |
| logs/8-2.log | 6176964972e0abd2c98f4800bec81a403935f03693137ca85cb22cf3756cfd2c |
| logs/8-3.log | 7a38c285f51e2675b27f6e001018d34e9a543211888080a61e62f4bab9164821 |

The reader compares every copy of a species' verdict it finds across the
results, the progress files and the logs. A species scored in a lost attempt
and again later has two copies. "Copies that disagree" is expected to be 0.
If it is not 0, that count is reported with the read as a fault of the
resume, and the PC and Steve decide what it means. The stopping rule does
not change.

## The reader

- **read_seed2_v3.py**, sha256 LF
  14de29c1afc8be4afb742acadd53d8ddbe43bea28c7cecd75940d198dfa17107, beside
  read_seed2_v2.py (78d2356c…). It differs from v2 only in what it expects:
  it takes the expected species from seed 2's layout as well as from the
  saved results. A species in no file and no log is then counted unscored in
  the per-learner table, where v2 left it out. A failed row is not a scored
  one, so it is unscored too.
- **What it does not change:** the success test's four parts were already
  counted against the layout's totals in v2 (800 and 160 geography tests per
  learner), and are computed the same way.
- **The checks:**
  - Its layout matches the one the R code builds, species for species.
  - On seed 1's two runs (run-20261120, run-20261121), its success-test lines
    and verdicts are identical to v2's.
  - On the incomplete 11/20 run, its table counts the 87 species that no
    file or log holds. That run's results were already read and registered,
    so nothing was learned from them here.
- **Its header lists the four changes.**

## Unchanged

- **The success test:** as amended on 2026-11-23, for Maxent and random
  forest at 200+ sites and over every band, with unscored species counted
  both ways.
- **What happens if it does not hold:** the registered entry's "If the test
  does not hold" applies.
- **The species, seed, commit, image, command and arguments**, as above.
