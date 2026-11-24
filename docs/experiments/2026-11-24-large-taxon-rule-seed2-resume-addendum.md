# Addendum to the note on resuming seed 2 (the launch time)

Drafted on 2026-11-24 by the method lane, before Steve's answer (draft
sha256 LF 26c4711e2fc083c6ae23f9e70891fe6e8661181c2f77f0b5e1bf94fad239ebb1).
The method lane's statement, as it wrote it: "No seed-2 verdict, score, p,
pass count, pass rate or per-species time had been seen by the method lane
when it was written, and none had been reported to it. Nothing in
calibration/run-20261123/job/ has been opened since the note." Completed
from that draft by the paper lane at 13:31 UTC on 2026-11-24, before any
resumed launch. The paper lane has seen no seed-2 result of any kind, none
has been reported to it, and it has opened nothing in
calibration/run-20261123/job/.

It amends docs/experiments/2026-11-23-large-taxon-rule-seed2-resume-note.md
(sha256 LF 516752318672ddfbb1c1640568686bc8ccaff8c387e8af89ebfb040d0dc1525d),
which is left as it was. It applies under Steve's answer to ops at
13:17:30 UTC 2026-11-24, to a question ops asked at 09:34:33 UTC: "Skip
11/25 nightly once (Rec.)".

**What the note fixed.** The resumed attempt was to launch after the 11/24
nightly and end by 06:45 UTC on 11/25. If the nightly ended after 11:00 UTC,
MAX_HOURS was to be lowered to meet that end, never below 18 h. Below 18 h,
ops was to hold and ask Steve.

**What changed, and why.** The 11/24 nightly started at 07:06 UTC and ran
long: a first refit at 2 km of 4,580 models on 4 workers, whose pull passed
its QA. It was still running at 13:25 UTC, already past 12:45 UTC, the
latest start for 18 h. So the 06:45 UTC end could not be met at 18 h or
more, and ops held and asked Steve. The change is to the clock only.
Nothing in the run was seen, and nothing seen decided it.

**Terms replaced.** Two terms of the note are replaced: the 06:45 UTC end on
11/25, and the rule that trims MAX_HOURS to meet it. The cap is 20 h,
untrimmed. The note's rule that the attempt never runs beside a nightly is
kept (below).

**What is unchanged:**
- the same study job, study-20261123T081504Z-6e41f5ca;
- the same image, study-d04c60a7aa2772ad98354a69f8bb9c2526e92b60;
- the same arguments and launch script, resume.sh, sha256 b87256a5…;
- 8 on-demand r7i.2xlarge workers;
- MAX_HOURS 20, untrimmed;
- one launch, and the stopping rule as registered;
- the one read, with read_seed2_v3.py (14de29c1…), when the attempt ends;
- nothing in job/ read before then;
- the dollar ceiling, $84.67 (8 × 20 h × $0.5292/h).

**New end.** Ops launches resume.sh when the 11/24 nightly has ended. The
attempt's latest end is its launch time plus 20 h, set by the launcher's job
deadline (R/ec2.R:423), each worker's timer counting from its own boot. Ops
records the nightly's end time and the launch time, and both go into the
hand-over with the logs.

**No run beside a nightly.** The 11/25 nightly is paused for that one night.
Ops runs it by hand after the attempt ends, and the timer is back on after
that.
