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


# ---- Oh My Posh Installation & Configuration on PVC ----
OMP_BIN_DIR="$DATA_DIR/.local/bin"
OMP_THEME_DIR="$DATA_DIR/.config/oh-my-posh"
OMP_THEME_FILE="$OMP_THEME_DIR/catppuccin_frappe.omp.json"

# 1. Download Oh My Posh to the PVC if it doesn't exist
if [ ! -x "$OMP_BIN_DIR/oh-my-posh" ]; then
	log "Installing Oh My Posh to PVC..."
	mkdir -p "$OMP_BIN_DIR"
	curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$OMP_BIN_DIR"
fi

# 2. Download the Theme to the PVC if it doesn't exist
if [ ! -f "$OMP_THEME_FILE" ]; then
	log "Downloading Oh My Posh theme to PVC..."
	mkdir -p "$OMP_THEME_DIR"
	curl -sL https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/catppuccin_frappe.omp.json -o "$OMP_THEME_FILE"
fi

# 3. Ensure a default .bashrc exists if the PVC is completely empty
BASHRC="$DATA_DIR/.bashrc"
if [ ! -f "$BASHRC" ]; then
	log "Initializing default .bashrc from /etc/skel..."
	cp /etc/skel/.bashrc "$BASHRC"
fi

# 4. Inject initialization into .bashrc if not already present
if ! grep -q "oh-my-posh init bash" "$BASHRC"; then
	log "Adding Oh My Posh configuration to .bashrc..."
	{
		echo ""
		echo '# ---- Oh My Posh ----'
		echo "export PATH=\"$OMP_BIN_DIR:\$PATH\""
		echo "eval \"\$($OMP_BIN_DIR/oh-my-posh init bash --config $OMP_THEME_FILE)\""
	} >> "$BASHRC"
fi


# Start SSH daemon on port 2222
log "Starting SSH Daemon..."
/usr/sbin/sshd

exec "$@"