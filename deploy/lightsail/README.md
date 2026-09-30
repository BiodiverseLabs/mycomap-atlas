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
```

| Path | What | Owner |
|---|---|---|
| `/etc/atlas/atlas.env` | every setting and secret ([atlas.env.example](atlas.env.example)) | root:atlas 640 |
| `/etc/atlas/image.env` | which image is deployed (written by deploy.sh) | root |
| `/srv/atlas/data` | the data directory: the pull, and the release without rasters | atlas |
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
- **Logs**: `journalctl -u atlas-api`, `journalctl -u atlas-nightly`, and
  nginx's in `/var/log/nginx/`.
- **Is it up**: `curl -s http://127.0.0.1:5100/api/status` on the box.

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
HTTP is redirected.
