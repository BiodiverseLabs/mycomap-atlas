# Functions setup-box.sh uses, kept apart so test-box-config.sh can run them
# on Ubuntu 24.04 itself.

# Write HOST's ed25519 SSH host key to FILE, or refuse (exit 1) without
# touching FILE when the key cannot be read. The operator compares the key's
# fingerprint with one they already trust before anything uses it.
atlas_scan_host_key() {
  local host="$1" file="$2" scanned
  # Ubuntu 24.04's ssh-keyscan has no -q; its chatter goes to stderr.
  scanned="$(ssh-keyscan -T 10 -t ed25519 "$host" 2>/dev/null || true)"
  if ! grep -q ' ssh-ed25519 ' <<<"$scanned"; then
    echo "Could not read $host's SSH host key. Is port 22 open to this server?" >&2
    exit 1
  fi
  printf '%s\n' "$scanned" > "$file"
}
