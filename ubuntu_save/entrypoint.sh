#!/bin/sh
# Reinstall, onto this fresh container, every package recorded in the PVC manifest.
set -e

DATA_DIR="${PERSISTENT_DIR:-/data}"
MANIFEST="$DATA_DIR/installed.manifest"

mkdir -p "$DATA_DIR/apt-cache"
chown -R _apt:root "$DATA_DIR/apt-cache"

log() { printf '[entrypoint] %s\n' "$*"; }

if [ -f "$MANIFEST" ]; then
	MISSING=""
	while read -r pkg; do
		[ -z "$pkg" ] && continue
		case "$pkg" in \#*) continue;; esac
		if ! dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
			MISSING="$MISSING $pkg"
		fi
	done < "$MANIFEST"

	if [ -n "$MISSING" ]; then
		log "restoring from manifest:$MISSING"
		apt-get update

		# Temporarily disable 'exit on error' so a bad package doesn't crash the container
		set +e 

		# Try bulk install first (fastest)
		# shellcheck disable=SC2086
		if ! apt-get install -y --no-install-recommends $MISSING; then
			log "WARNING: Bulk install failed. Falling back to individual installation..."

			# Loop through and install one by one
			for pkg in $MISSING; do
				if ! apt-get install -y --no-install-recommends "$pkg"; then
					log "ERROR: Failed to install $pkg. Skipping and removing from manifest."
					# Actively heal the system by removing the broken package from the list
					sed -i "/^${pkg}$/d" "$MANIFEST"
				fi
			done
		fi

		# Turn 'exit on error' back on
		set -e

		rm -rf /var/lib/apt/lists/*
		log "restore complete"
	else
		log "all manifest packages already present"
	fi
else
	log "no manifest on this PVC yet (fresh) -- nothing to restore"
fi

# Keep the manifest in sync with reality
apt-mark showmanual > "$MANIFEST.new" 2>/dev/null && mv "$MANIFEST.new" "$MANIFEST" || true

exec "$@"