#!/bin/bash
# Deploy one commit of Atlas to this server.
#
#   sudo /usr/local/lib/atlas/deploy.sh <full commit sha>
#
# Pulls the release image CI published for that commit, checks the image says
# it is that commit, puts its web app in /srv/atlas/web (the previous one is
# kept as web.previous), points the API and the nightly job at the image,
# restarts the API and waits for it to answer. Nothing is built here.
#
# Roll back by deploying the previous commit.
set -euo pipefail

sha="${1:-}"
if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "usage: deploy.sh <full 40-character commit sha>" >&2
  exit 64
fi
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo." >&2; exit 1; fi

image="ghcr.io/biodiverselabs/mycomap-atlas:$sha"
web=/srv/atlas/web

echo "== pulling $image"
docker pull -q "$image"
recorded="$(docker run --rm --entrypoint printenv "$image" ATLAS_COMMIT)"
if [ "$recorded" != "$sha" ]; then
  echo "the image says it is commit '$recorded', not $sha; nothing changed" >&2
  exit 1
fi

echo "== web app"
container="$(docker create "$image")"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
rm -rf "$web.next"
docker cp "$container:/opt/atlas-web" "$web.next"
if [ ! -f "$web.next/index.html" ]; then echo "the image has no web app; nothing changed" >&2; exit 1; fi
# The nightly job writes the sitemap, not the image: keep the last one.
if [ -f /srv/atlas/data/sitemap.xml ]; then cp /srv/atlas/data/sitemap.xml "$web.next/sitemap.xml"; fi
chmod -R go=rX "$web.next"
rm -rf "$web.previous"
[ -d "$web" ] && mv "$web" "$web.previous"
mv "$web.next" "$web"

echo "== API"
previous="$(sed -n 's/^ATLAS_IMAGE=//p' /etc/atlas/image.env 2>/dev/null || true)"
echo "ATLAS_IMAGE=$image" > /etc/atlas/image.env
systemctl restart atlas-api
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null http://127.0.0.1:5100/api/status; then
    echo "API answering, commit $sha"
    break
  fi
  sleep 2
done
curl -fsS -o /dev/null http://127.0.0.1:5100/api/status || {
  echo "the API did not answer within 2 minutes: journalctl -u atlas-api" >&2
  exit 1
}

# Keep this image and the one it replaced, for a quick rollback; older ones
# only fill the disk (each is several GB).
for old in $(docker image ls --format '{{.Repository}}:{{.Tag}}' ghcr.io/biodiverselabs/mycomap-atlas); do
  [ "$old" = "$image" ] || [ "$old" = "$previous" ] || docker image rm "$old" >/dev/null 2>&1 || true
done
