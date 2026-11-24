# The Atlas server

atlas.mycomap.org runs on one small Lightsail box (2 GB, Ubuntu 24.04). It
fits nothing: it serves the web app and the API, and once a night it pulls
the validated records from mycomap.org, plans what changed, and has EC2 spot
workers fit it (deploy/aws/). Everything it runs is the release image of one
commit, which CI publishes; nothing is built on the box.

```
Cloudflare ──443──► nginx ──► /srv/atlas/web          the app, copied out of the image
                        └───► 127.0.0.1:5100          the API container (atlas-api.service)
07:00 UTC  atlas-nightly.timer ──► nightly.sh ──► `atlas nightly` in the image
                                               └► `pull-release --no-rasters`, restart the API
                                               └► `sitemap`, copied to /srv/atlas/web/sitemap.xml
every 5 min  atlas-uptime.timer ──► uptime.sh ──► GET 127.0.0.1:5100/api/status
on failure   atlas-alert@<unit> ──► alert.sh ──► journal, /srv/atlas/data/health, login banner
```

| Path | What | Owner |
|---|---|---|
| `/etc/atlas/atlas.env` | every setting and secret ([atlas.env.example](atlas.env.example)) | root:atlas 640 |
| `/etc/atlas/image.env` | which image is deployed (written by deploy.sh) | root |
| `/srv/atlas/data` | the data directory: the pull, and the release without rasters | atlas |
| `/srv/atlas/data/health` | one `<check>.json` per check: ok or failed, since when, why | atlas |
| `/srv/atlas/web` | the web app of the deployed commit (`web.previous` is the one before) | root |
| `/home/atlas/.ssh` | the key and host entry for mycomap.org's read-only SQL route | atlas |
| `/etc/ssl/atlas` | the Cloudflare origin certificate | root 700 |

The containers run as uid 10001, the same as the `atlas` account, so they
read the SSH key and write the data directory with no extra permissions. The
API container shares the host's network and listens on 127.0.0.1 only; nginx
reaches it from 127.0.0.1, the one peer whose `X-Forwarded-For` it believes,
and nginx replaces that header with the visitor's address from Cloudflare.

## Setting it up

1. **Lightsail** (administrator, AWS CLI): a 2 GB Ubuntu 24.04 instance, a
   static IP, and a firewall with SSH from the operator's address only and 80
   and 443 from [Cloudflare's addresses](https://www.cloudflare.com/ips/) only.
2. **Cloudflare**: an `A` record for `atlas` to the static IP, proxied; SSL
   mode Full (strict); an origin certificate for `atlas.mycomap.org`.
3. **On the box**, from a checkout of this repository:
   ```bash
   sudo bash deploy/lightsail/setup-box.sh --sql-host=<mycomap.org's address> [--claude-key='<key>']
   ```
   It ends by printing the server's SQL key and mycomap.org's host key
   fingerprint. Compare the fingerprint with the one you already trust.
4. **On mycomap.org** (its `deploy/readonly-sql/atlas-install.sh`): give the
   server's key and static IP to the `atlas_ro` installer.
5. **The settings**: fill in `/etc/atlas/atlas.env` from
   [atlas.env.example](atlas.env.example) (`sudoedit /etc/atlas/atlas.env`), and
   put the origin certificate and key in `/etc/ssl/atlas/origin.pem` and
   `origin.key` (mode 600). Then `sudo nginx -t && sudo systemctl reload nginx`.
6. **Deploy** the commit to run:
   ```bash
   sudo /usr/local/lib/atlas/deploy.sh <full commit sha>
   ```

## Every day

- **Deploy** a new commit, or roll back to an older one: the same
  `deploy.sh <sha>`. The commit must be on main (CI publishes its image) and
  the package public.
- **Run the nightly job now**: `sudo systemctl start atlas-nightly`.
- **Draw the link-preview cards** for the release the box serves, beside it
  and never in it (R/card.R), and publish them for the next pull. The
  nightly job does this after every pull; by hand, for a release pulled
  before cards existed:
  ```bash
  source /etc/atlas/image.env
  sudo docker run --rm --name atlas-cards --network host --memory 400m \
    --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data "$ATLAS_IMAGE" build-cards --upload
  ```
  The API serves them as soon as they are drawn, with no restart. Without
  `--upload` they are drawn on the box only and a later pull removes them.
- **Logs**: `journalctl -u atlas-api`, `journalctl -u atlas-nightly`, and
  nginx's in `/var/log/nginx/`.
- **Is it up**: `curl -s http://127.0.0.1:5100/api/status` on the box.

## When something fails

Two things are watched: the nightly job (`atlas-nightly`), and the API
answering `GET /api/status` on 127.0.0.1:5100 (`atlas-uptime`, every 5
minutes, from the first deploy on; it retries for about two minutes, so a
restart is not an outage). When either fails, its `OnFailure=` starts
`atlas-alert@<unit>`, which runs [alert.sh](alert.sh). It records the failure
in three places:

- **The login banner**: whoever signs in to the box next sees
  `ATLAS: atlas-nightly failing since ... (n failures): ...`.
- **The journal**, as an error tagged `atlas-alert`:
  `journalctl -t atlas-alert` lists every failure and recovery. The detail is
  in the failed unit's own journal, which the message names.
- **`/srv/atlas/data/health/<unit>.json`**: `state` (`ok` or `failed`),
  `since`, `checked`, `failures` and `message`. It is inside the data
  directory the API mounts at `/data`, so the API can show it.

The next good run of the same unit sets the file back to `ok` and logs the
recovery. Nothing is sent anywhere: the box has no mailer. Getting an alert
to someone who is not signing in needs an outside service (a mail relay such
as SES, or a webhook), and the place to add it is alert.sh.

The banner also carries a note that is no failure:
`ATLAS: pull-left-out since ...: n names left the pull as not fungi: ...`. A pull
leaves out a name GBIF matches exactly, at species rank, in another kingdom
(`R/qa.R`), mostly plant specimens from the pool runs, and names each one new here,
in its `qa-<stamp>.json` and in the nightly's journal. If one is a fungus, add it
to `occurrences/kingdom-allow.txt`: it comes back with the next pull. Once read,
clear the note with `sudo /usr/local/lib/atlas/alert.sh --ok pull-left-out`.

### When the pull's QA stops

A pull whose QA report stops (`R/qa.R`) plans nothing. The nightly fails, so it
shows as `atlas-nightly failing` in the banner, the journal and the health file,
each night it stops. The site keeps its last release.

A pull is compared with the **baseline**, `occurrences/qa-baseline.json`: the
last pull the gate let through. So a stop does not clear itself the next night.
It stays a stop every night until the change goes away or someone accepts it.
To see why it stopped, read `occurrences/qa-latest.json` (`stops`, and each
check's `why`). The failed run's journal gives the exact command. To accept the
stop:

```bash
./atlas accept-qa --accept-qa=<pull stamp>:<check>[,<check>...]
```

This names the current pull's stamp and every stop it holds. It plans nothing:
the pull becomes the baseline, the next nightly is compared with it and runs as
usual, and the banner clears on that night's success. To fit from the stopped
pull itself, `plan-job --accept-qa=...` does the same and plans as well.

While a stop runs for several nights, every check is compared with the same,
older baseline, so ordinary drift can add further stops night after night. The
command must name every stop the current pull holds; the stopped run's error
lists them all, in the form the command takes.

A pull becomes the baseline when the gate lets it through, before anything is
fitted, so a night whose QA passes but whose fit then fails has still moved the
baseline.

### Finishing the current release by hand

Finishing (R/finish.R) is what the nightly does after fitting: it draws every
map in whole 50 km blocks of its own accessible area (built again from the
pull its job fitted it on), redraws the pictures, counts by state again and
rebuilds the combined maps, the Explore index and the prior. It runs on one
EC2 worker and refits nothing. When finishing changes its rule (a new
`ATLAS_FINISH_VERSION`), the current release is finished again once, by day
and under watch, rather than left to a night that a QA stop could cut short:

```bash
# first, read only: how many maps the finish will take off for want of a pull
docker run --rm --name atlas-finish-plan --network host --memory 1g \
  --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data \
  "$ATLAS_IMAGE" finish-plan
# after a nightly has ended, with the owner's OK for the EC2 run
docker run --rm --name atlas-finish --network host --memory 1g \
  --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data \
  "$ATLAS_IMAGE" finish-current
# then, as the nightly does after it
docker run --rm --name atlas-pull --network host --memory 1g \
  --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data \
  "$ATLAS_IMAGE" pull-release --no-rasters && sudo systemctl restart atlas-api
docker run --rm --name atlas-cards --network host --memory 1g \
  --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data \
  "$ATLAS_IMAGE" build-cards --upload
```

`finish-plan` prints how many of the current release's maps have their record
set in a pull the store keeps, and how many do not. A map not found is taken
off by the finish (`map: false` in the index) until it is fitted again; a map
found can still be taken off if the area built from its pull does not give
exactly the map as stored. The finished release counts both under
`finished.not_drawn` (`not_found`, `mismatch`), and the finish's log line
says them.

The nightly, a job run on EC2 and `finish-current` each hold the box's
orchestrator lock (`/srv/atlas/data/locks/orchestrator`), and `finish-current`
refuses to start while a nightly or a job holds it. The next nightly finds the
release finished and skips the step.

Map pictures and cards are served with a version in their address and cached
for a year. Once the first release finished under a new rule is live, purge
the zone's cache in the Cloudflare dashboard, so cached pictures are refreshed.

**Rolling back to an image older than the finishing rule:** promote the
release before the finish first (`./atlas promote-release --release=<its
previous>`; the finished release names it as `previous`), then deploy the
older image. An older image never runs a nightly while a release finished
under a newer rule is current. The paper's frozen release
(`ATLAS_FROZEN_RELEASES`) is never finished again.

To check the alerting itself:

```bash
sudo systemctl start atlas-alert@atlas-nightly   # a pretend failure
sudo /usr/local/lib/atlas/alert.sh --summary      # the banner's line
sudo /usr/local/lib/atlas/alert.sh --ok atlas-nightly
```

## Zenodo drafts that publish themselves

An archive version is still made by hand (`archive-release`, after
`cells-now` for a models version), and stops at a draft. Once the timer
below is on, a draft publishes itself 3 days later unless a person deletes it
on zenodo.org first (`archive-auto-publish`, R/autopublish.R). Publishing is
permanent. **The timer is off, and its files are not on atlas-box**, until
Steve decides on auto-publish (installing it, below).

- **The token** is in `/etc/atlas/zenodo.env`, root:root, mode 600, one
  line `ZENODO_TOKEN=...` (a personal access token with `deposit:write` and
  `deposit:actions`, from the account that owns the Atlas records). It is
  kept apart from `atlas.env`, which every container gets, so only this
  unit's container is given it. Zenodo's tokens cannot be limited to one
  record: this one can publish or edit any of that account's uploads.
  Revoking it on zenodo.org makes the next run fail, loudly. Optional, in the
  same file: `ATLAS_ZENODO_PUBLISH_AFTER_DAYS` (a number of days, 1 or more,
  or `off`).
- **The timer**: `atlas-zenodo-publish.timer`, daily at 15:00 UTC, runs
  [zenodo-publish.sh](zenodo-publish.sh). It runs the command in the deployed
  image with the data directory mounted, so the ledger the site serves
  changes with the store's. It is not part of the nightly: it takes the
  nightly's lock and skips the day while the nightly runs (the nightly's
  pull-release rewrites `/data/archives`), and a skipped day only means a
  draft publishes a day later.
- **A refusal** (a draft changed on Zenodo since it was made, or one made
  before this command existed, or a published version whose description has
  text a person added there) leaves the draft, fails the unit and puts it in
  the banner, every day, until a person publishes it with
  `archive-publish --series=<series>` or deletes it on zenodo.org.
- **Logs**: `journalctl -u atlas-zenodo-publish`. Each series gets one line:
  `nothing waiting`, `waiting` (with the date it will publish), `published`,
  `published by hand`, `discarded`, `refused` or `failed`, with why.

Until Steve OKs drafts publishing themselves, the timer stays off and nothing
publishes on its own: today each Zenodo record needs his explicit OK, and the
token is deleted after each run. On a fresh box `setup-box.sh` installs the
script and both units **disabled** (it never enables or starts them, and never
writes the token file). **Never re-run `setup-box.sh` on atlas-box** to get
them: it enables `atlas-nightly.timer` and rewrites the box's configuration.

Installing it on atlas-box, by hand, only with Steve's OK. The three files
come from the commit he approved, and each must have the hash that commit
holds:

```bash
# On a machine with the repo: the hashes of the approved commit (<sha>).
for f in zenodo-publish.sh systemd/atlas-zenodo-publish.service systemd/atlas-zenodo-publish.timer; do
  printf '%s  %s\n' "$(git show "<sha>:deploy/lightsail/$f" | sha256sum | cut -d' ' -f1)" "$(basename "$f")"
done
# On the box, in a folder holding the three copied files: the same hashes, or stop.
sha256sum zenodo-publish.sh atlas-zenodo-publish.service atlas-zenodo-publish.timer
sudo install -m 755 -o root -g root zenodo-publish.sh /usr/local/lib/atlas/zenodo-publish.sh
sudo install -m 644 -o root -g root atlas-zenodo-publish.service atlas-zenodo-publish.timer /etc/systemd/system/
sudo systemctl daemon-reload
```

Installed, it still does nothing until the token file exists and the timer
is enabled. Each of those is a step of its own, with Steve's OK:

```bash
# the token file, written by the token's owner:
sudo install -m 600 -o root -g root /dev/null /etc/atlas/zenodo.env   # then add ZENODO_TOKEN=...
sudo systemctl start atlas-zenodo-publish      # once by hand; read its journal
sudo systemctl enable --now atlas-zenodo-publish.timer
```

## A trial run

Before the timer is trusted with a whole night's work, fit a few taxa end to
end: records pulled, a job planned, a spot worker launched, its models
published, the site showing them. On the box, after deploying the commit:

```bash
# Once per box: the guild table Maxent orders its predictors by. It is looked
# up, never published; the plan ships it to the workers with the job.
sudo /bin/sh -c '. /etc/atlas/image.env; docker run --rm --network host \
  --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data "$ATLAS_IMAGE" fetch-guilds'

# The trial, under systemd so it outlives the terminal: Maxent for the three
# richest taxa. Maxent is the slow model; allow half an hour.
sudo systemd-run --unit=atlas-trial --collect -p EnvironmentFile=/etc/atlas/image.env \
  /bin/sh -c 'exec docker run --rm --name atlas-trial --network host --memory 1g \
  --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data \
  -v /home/atlas/.ssh:/home/atlas/.ssh:ro "$ATLAS_IMAGE" nightly --algorithms=maxnet --limit=3'

sudo journalctl -fu atlas-trial          # watch it
sudo systemctl stop atlas-trial          # stop it, then check no worker is left (deploy/aws/README.md)
```

It has worked when the journal ends with a published release, the release
lists three models (`/api/models` on the site), and no worker is left running.
Then bring the site up to it and let the timer run:

```bash
sudo /bin/sh -c '. /etc/atlas/image.env; docker run --rm --network host \
  --env-file /etc/atlas/atlas.env -v /srv/atlas/data:/data "$ATLAS_IMAGE" pull-release --no-rasters'
sudo systemctl restart atlas-api
sudo systemctl enable --now atlas-nightly.timer
```

A blank line and "Execution halted" in the journal is R being interrupted,
not an error of its own. A model fitted under an older design is stale under
a newer one, so the first night after a change of method refits every taxon:
raise `--limit` in steps (3, then 50) before leaving it to the timer.

## Checking the configuration

```bash
bash deploy/lightsail/test-box-config.sh                    # Docker: the scripts, the units, nginx
bash deploy/lightsail/test-box-config.sh --check-cloudflare # Cloudflare's addresses still match
```

The first runs in CI. It puts Ubuntu 24.04's own nginx in front of a stand-in
API and checks that the API and sign-in reach it, that a client's
`X-Forwarded-For` never does, that an API error is the API's own answer, that
app routes fall back to the app and missing assets do not, and that plain
HTTP is redirected. It also installs the monitoring units, has systemd check
them, and runs alert.sh and uptime.sh on the box image.
