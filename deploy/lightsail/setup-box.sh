#!/bin/bash
# One-time setup of the Atlas server: Ubuntu 24.04 on a 2 GB Lightsail box.
#
#   sudo bash setup-box.sh --sql-host=<mycomap.org's address> [--claude-key='<public key>']
#
# Run from a checkout of this repository on the box. It is safe to run again.
# It sets up:
#   - 2 GB of swap: the API and the nightly job share 2 GB of memory;
#   - Docker (container output to the journal) and nginx;
#   - the atlas account, uid 10001 like the image's user, which owns the data
#     directory and the key for mycomap.org's read-only SQL route;
#   - /etc/atlas/atlas.env, empty and readable only by root and atlas;
#   - nginx's site, the systemd units for the API and the nightly job, and the
#     scripts they run;
#   - optionally, a read-only login for Claude: journal and nginx logs, no
#     sudo, no Docker, no data.
# It does not start anything: fill in atlas.env, install the TLS certificate,
# then run deploy.sh (README.md walks through it).
set -euo pipefail

SQL_HOST=""
CLAUDE_KEY=""
for arg in "$@"; do
  case "$arg" in
    --sql-host=*) SQL_HOST="${arg#*=}" ;;
    --claude-key=*) CLAUDE_KEY="${arg#*=}" ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo." >&2; exit 1; fi
if [ -z "$SQL_HOST" ]; then echo "Pass --sql-host=<mycomap.org's address>." >&2; exit 64; fi
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"

echo "== swap"
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=10' > /etc/sysctl.d/90-atlas-swap.conf
sysctl -q -p /etc/sysctl.d/90-atlas-swap.conf

echo "== packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io nginx curl unattended-upgrades >/dev/null
install -d -m 755 /etc/docker
echo '{ "log-driver": "journald" }' > /etc/docker/daemon.json
systemctl enable --now docker >/dev/null
systemctl restart docker

echo "== the atlas account and its directories"
id atlas >/dev/null 2>&1 || useradd --uid 10001 --create-home --shell /usr/sbin/nologin atlas
# /srv/atlas itself is open to all, so nginx (www-data) reaches web/; the
# data directory in it, which holds the pull, stays atlas's alone.
install -d -o root -g root -m 755 /srv/atlas /srv/atlas/web /usr/local/lib/atlas
install -d -o atlas -g atlas -m 750 /srv/atlas/data
install -d -o root -g atlas -m 750 /etc/atlas
[ -f /etc/atlas/atlas.env ] || install -o root -g atlas -m 640 /dev/null /etc/atlas/atlas.env
chown root:atlas /etc/atlas/atlas.env
chmod 640 /etc/atlas/atlas.env

echo "== the key for mycomap.org's read-only SQL route"
install -d -o atlas -g atlas -m 700 /home/atlas/.ssh
if [ ! -f /home/atlas/.ssh/atlas_sql ]; then
  sudo -u atlas ssh-keygen -q -t ed25519 -N '' -C "atlas-server" -f /home/atlas/.ssh/atlas_sql
fi
cat > /home/atlas/.ssh/config <<CFG
Host mycomap-sql
  HostName $SQL_HOST
  User atlas_ro
  IdentityFile ~/.ssh/atlas_sql
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  BatchMode yes
CFG
if ! sudo -u atlas ssh-keygen -F "$SQL_HOST" -f /home/atlas/.ssh/known_hosts >/dev/null 2>&1; then
  atlas_scan_host_key "$SQL_HOST" /home/atlas/.ssh/known_hosts
fi
chown atlas:atlas /home/atlas/.ssh/config /home/atlas/.ssh/known_hosts
chmod 600 /home/atlas/.ssh/config /home/atlas/.ssh/known_hosts

echo "== nginx"
install -m 644 "$here/nginx/cloudflare-real-ip.conf" /etc/nginx/snippets/cloudflare-real-ip.conf
install -m 644 "$here/nginx/atlas-proxy.conf" /etc/nginx/snippets/atlas-proxy.conf
install -m 644 "$here/nginx/atlas.conf" /etc/nginx/sites-available/atlas
ln -sf /etc/nginx/sites-available/atlas /etc/nginx/sites-enabled/atlas
rm -f /etc/nginx/sites-enabled/default
install -d -o root -g root -m 700 /etc/ssl/atlas

echo "== the API and the nightly job"
install -m 755 "$here/nightly.sh" /usr/local/lib/atlas/nightly.sh
install -m 755 "$here/deploy.sh" /usr/local/lib/atlas/deploy.sh
for unit in atlas-api.service atlas-nightly.service atlas-nightly.timer; do
  install -m 644 "$here/systemd/$unit" "/etc/systemd/system/$unit"
done
systemctl daemon-reload
systemctl enable atlas-api.service atlas-nightly.timer >/dev/null

if [ -n "$CLAUDE_KEY" ]; then
  echo "== read-only login for Claude"
  id claude >/dev/null 2>&1 || useradd --create-home --shell /bin/bash claude
  # The journal (API, nightly job, containers) and nginx's logs; nothing else.
  usermod -G systemd-journal,adm claude
  install -d -o claude -g claude -m 700 /home/claude/.ssh
  printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding %s\n' "$CLAUDE_KEY" > /home/claude/.ssh/authorized_keys
  chown claude:claude /home/claude/.ssh/authorized_keys
  chmod 600 /home/claude/.ssh/authorized_keys
fi

echo
echo "Done. Next (README.md):"
echo "  1. Give mycomap.org this server's SQL key and address:"
echo "     $(cat /home/atlas/.ssh/atlas_sql.pub)"
echo "  2. Compare mycomap.org's host key with the one you know:"
ssh-keygen -l -f /home/atlas/.ssh/known_hosts | sed 's/^/     /'
echo "  3. Fill in /etc/atlas/atlas.env and put the origin certificate in /etc/ssl/atlas/."
echo "  4. sudo /usr/local/lib/atlas/deploy.sh <commit>"
