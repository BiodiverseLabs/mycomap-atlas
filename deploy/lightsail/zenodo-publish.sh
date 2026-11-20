#!/bin/bash
# Publish the Zenodo drafts whose grace period is over (`atlas
# archive-auto-publish`, R/autopublish.R), run by atlas-zenodo-publish.service.
#
# The Zenodo token lives in /etc/atlas/zenodo.env (root:root, mode 600), a
# file of its own so that only this container is given it: atlas.env goes to
# every container, the API's and the nightly's among them.
#
# Never while the nightly runs: its pull-release rewrites /data/archives from
# the store. A day skipped only means a draft publishes a day later.
#
# Exits non-zero when a draft is refused or Zenodo could not be read, so the
# unit fails and atlas-alert@ records it until a person acts.
set -uo pipefail
: "${ATLAS_IMAGE:?ATLAS_IMAGE is not set: deploy a commit first}"

token_file=/etc/atlas/zenodo.env
if [ ! -r "$token_file" ]; then
  echo "no $token_file: the Zenodo token goes there (ZENODO_TOKEN=...); nothing done" >&2
  exit 1
fi

exec 9>/run/atlas-nightly.lock
if ! flock --nonblock 9; then
  echo "the nightly is running; waiting drafts are looked at on the next run"
  exit 0
fi

docker run --rm --name atlas-zenodo-publish --network host --memory 1g \
  --env-file /etc/atlas/atlas.env \
  --env-file "$token_file" \
  -v /srv/atlas/data:/data \
  "$ATLAS_IMAGE" archive-auto-publish
