#!/bin/sh
# Reinstall, onto this fresh container, every package recorded in the PVC manifest.
# We keep set -e for major structural failures, but protect minor file operations.
set -e

DATA_DIR="${PERSISTENT_DIR:-/data}"
MANIFEST="$DATA_DIR/installed.manifest"

# Fail-safe directory creation
mkdir -p "$DATA_DIR/apt-cache" || true
chown -R _apt:root "$DATA_DIR/apt-cache" || true

log() { printf '[entrypoint] %s\n' "$*"; }

# ---- Persistent System Directories ----
PERSIST_DIRS="/etc/apt/sources.list.d /etc/apt/keyrings /etc/apt/preferences.d /usr/share/postgresql-common"

log "Mapping persistent system directories to PVC..."
for DIR in $PERSIST_DIRS; do
	SAFE_NAME=$(echo "$DIR" | tr '/' '_')
	PVC_TARGET="$DATA_DIR/system_persist$SAFE_NAME"

	if [ ! -d "$PVC_TARGET" ]; then
		mkdir -p "$PVC_TARGET" || true
		if [ -d "$DIR" ]; then
			cp -a "$DIR/." "$PVC_TARGET/" 2>/dev/null || true
		fi
	fi

	# Fail-safe symlinking
	rm -rf "$DIR" 2>/dev/null || true
	mkdir -p "$(dirname "$DIR")" || true
	ln -sf "$PVC_TARGET" "$DIR" || true
done

# ---- Persistent .bashrc ----
PVC_BASHRC="$DATA_DIR/system_persist_bashrc"

if [ ! -f "$PVC_BASHRC" ]; then
	log "Initializing persistent .bashrc on PVC..."
	if [ -f /root/.bashrc ] && [ ! -L /root/.bashrc ]; then
		cp /root/.bashrc "$PVC_BASHRC" || true
	else
		cp /etc/skel/.bashrc "$PVC_BASHRC" || true
	fi
	
	# Inject CUDA paths
	echo 'export PATH="/usr/local/cuda/bin:$PATH"' >> "$PVC_BASHRC" || true
	echo 'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"' >> "$PVC_BASHRC" || true
	
	# Inject NVM Initialization
	{
		echo ''
		echo '# ---- NVM (Node Version Manager) ----'
		echo 'export NVM_DIR="/usr/local/nvm"'
		echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
		echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
	} >> "$PVC_BASHRC" || true
fi

# Force symlink, ignore errors if it fails
rm -f /root/.bashrc 2>/dev/null || true
ln -sf "$PVC_BASHRC" /root/.bashrc || true

# ---- Package Restoration ----
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
		
		apt-get update || true
		
		# Turn off error-crashing completely for package installation
		set +e 

		# shellcheck disable=SC2086
		if ! apt-get install -y --no-install-recommends $MISSING; then
			log "WARNING: Bulk install failed. Falling back to individual installation..."
			for pkg in $MISSING; do
				if ! apt-get install -y --no-install-recommends "$pkg"; then
					log "ERROR: Failed to install $pkg. Skipping and removing from manifest."
					sed -i "/^${pkg}$/d" "$MANIFEST" || true
				fi
			done
		fi

		# Turn error-crashing back on
		set -e
		
		rm -rf /var/lib/apt/lists/* || true
		log "restore complete"
	else
		log "all manifest packages already present"
	fi
else
	log "no manifest on this PVC yet (fresh) -- nothing to restore"
fi

apt-mark showmanual > "$MANIFEST.new" 2>/dev/null && mv "$MANIFEST.new" "$MANIFEST" || true

# ---- Shared Persistent Bin Directory ----
LOCAL_BIN_DIR="$DATA_DIR/.local/bin"
mkdir -p "$LOCAL_BIN_DIR" || true

# ---- Oh My Posh Installation & Configuration on PVC ----
OMP_THEME_DIR="$DATA_DIR/.config/oh-my-posh"
OMP_THEME_FILE="$OMP_THEME_DIR/catppuccin_frappe.omp.json"

if [ ! -x "$LOCAL_BIN_DIR/oh-my-posh" ]; then
	log "Installing Oh My Posh to PVC..."
	curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$LOCAL_BIN_DIR" || true
fi

if [ ! -f "$OMP_THEME_FILE" ]; then
	log "Downloading Oh My Posh theme to PVC..."
	mkdir -p "$OMP_THEME_DIR" || true
	curl -sL https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/catppuccin_frappe.omp.json -o "$OMP_THEME_FILE" || true
fi

# Inject initialization into the PERSISTENT .bashrc
if [ -f "$PVC_BASHRC" ] && ! grep -q "oh-my-posh init bash" "$PVC_BASHRC"; then
	log "Adding Oh My Posh configuration to .bashrc..."
	{
		echo ""
		echo '# ---- Oh My Posh ----'
		echo "export PATH=\"$LOCAL_BIN_DIR:\$PATH\""
		echo "eval \"\$($LOCAL_BIN_DIR/oh-my-posh init bash --config $OMP_THEME_FILE)\""
	} >> "$PVC_BASHRC" || true
fi

# ---- Persistent .bash_profile ----
PVC_BASH_PROFILE="$DATA_DIR/system_persist_bash_profile"

if [ ! -f "$PVC_BASH_PROFILE" ]; then
	log "Initializing persistent .bash_profile on PVC..."
	{
		echo '# Load Swarm/system profile first'
		echo 'if [ -f ~/.profile ]; then'
		echo '    . ~/.profile'
		echo 'fi'
		echo ''
		echo '# Load custom bashrc SECOND to override Swarm PATH resets'
		echo 'if [ -f ~/.bashrc ]; then'
		echo '    . ~/.bashrc'
		echo 'fi'
	} > "$PVC_BASH_PROFILE" || true
fi

# Force symlink, ignore errors if it fails
rm -f /root/.bash_profile 2>/dev/null || true
ln -sf "$PVC_BASH_PROFILE" /root/.bash_profile || true

exec "$@"