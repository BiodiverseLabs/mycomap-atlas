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
