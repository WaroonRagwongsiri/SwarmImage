#!/bin/bash
# Reinstall, onto this fresh container, every package recorded in the PVC manifest.
# We keep set -e for major structural failures, but protect minor file operations.
set -e

DATA_DIR="${PERSISTENT_DIR:-/root}"
MANIFEST="$DATA_DIR/installed.manifest"

# Fail-safe directory creation
mkdir -p "$DATA_DIR/apt-cache" || true
chown -R _apt:root "$DATA_DIR/apt-cache" || true

log() { printf '[entrypoint] %s\n' "$*"; }

# -----------------------------------------------------------------------------
# 1. SYSTEM & PERSISTENCE PREP
# -----------------------------------------------------------------------------

# Mapping persistent system directories to PVC...
PERSIST_DIRS="/etc/apt/sources.list.d /etc/apt/keyrings /etc/apt/preferences.d /usr/share/postgresql-common /etc/jupyterhub"
for DIR in $PERSIST_DIRS; do
	SAFE_NAME=$(echo "$DIR" | tr '/' '_')
	PVC_TARGET="$DATA_DIR/system_persist$SAFE_NAME"

	if [ ! -d "$PVC_TARGET" ]; then
		mkdir -p "$PVC_TARGET" || true
		if [ -d "$DIR" ]; then
			cp -a "$DIR/." "$PVC_TARGET/" 2>/dev/null || true
		fi
	fi

	rm -rf "$DIR" 2>/dev/null || true
	mkdir -p "$(dirname "$DIR")" || true
	ln -sf "$PVC_TARGET" "$DIR" || true
done

# Initialize persistent bash profiles
PVC_BASHRC="$DATA_DIR/system_persist_bashrc"
if [ ! -f "$PVC_BASHRC" ]; then
	log "Initializing persistent .bashrc on PVC..."
	if [ -f /root/.bashrc ] && [ ! -L /root/.bashrc ]; then
		cp /root/.bashrc "$PVC_BASHRC" || true
	else
		cp /etc/skel/.bashrc "$PVC_BASHRC" || true
	fi
	
	echo 'export PATH="/opt/venv/bin:/usr/local/bin:$PATH"' >> "$PVC_BASHRC" || true
fi

# Force symlink, ignore errors if it fails
rm -f /root/.bashrc 2>/dev/null || true
ln -sf "$PVC_BASHRC" /root/.bashrc || true

# Shared Persistent Bin Directory & Oh My Posh
LOCAL_BIN_DIR="$DATA_DIR/.local/bin"
mkdir -p "$LOCAL_BIN_DIR" || true

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

if [ -f "$PVC_BASHRC" ] && ! grep -q "oh-my-posh init bash" "$PVC_BASHRC"; then
	log "Adding Oh My Posh configuration to .bashrc..."
	{
		echo ""
		echo '# ---- Oh My Posh ----'
		echo "export PATH=\"$LOCAL_BIN_DIR:\$PATH\""
		echo "eval \"\$($LOCAL_BIN_DIR/oh-my-posh init bash --config $OMP_THEME_FILE)\""
	} >> "$PVC_BASHRC" || true
fi

# Persistent .bash_profile (Fixes SSH Swarm overwrites)
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
rm -f /root/.bash_profile 2>/dev/null || true
ln -sf "$PVC_BASH_PROFILE" /root/.bash_profile || true

# -----------------------------------------------------------------------------
# 2. APT PACKAGE RESTORATION
# -----------------------------------------------------------------------------

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
		set +e 
		# shellcheck disable=SC2086
		if ! apt-get install -y --no-install-recommends $MISSING; then
			log "WARNING: Bulk install failed. Falling back to individual installation..."
			for pkg in $MISSING; do
				if ! apt-get install -y --no-install-recommends "$pkg"; then
					sed -i "/^${pkg}$/d" "$MANIFEST" || true
				fi
			done
		fi
		set -e
		rm -rf /var/lib/apt/lists/* || true
		log "restore complete"
	fi
fi
apt-mark showmanual > "$MANIFEST.new" 2>/dev/null && mv "$MANIFEST.new" "$MANIFEST" || true

# -----------------------------------------------------------------------------
# 3. JUPYTERHUB & WORKSPACE ENVIRONMENT PREP
# -----------------------------------------------------------------------------

log "Initializing JupyterHub shared workspace directories..."

mkdir -p /root/.jupyter \
	/root/.jupyter/nbi \
	/root/.jupyter/nbi/rules \
	/root/.jupyter/lab \
	/root/.jupyter/lab/user-settings \
	/root/.jupyter/lab/workspaces \
	/root/.local/share/jupyter \
	/root/.local/share/jupyter/runtime \
	/root/.local/share/jupyter/kernels \
	/root/.local/share/code-server \
	/root/.local/share/code-server/extensions \
	/root/.local/share/code-server/User \
	/root/.local/share/jupyterlab \
	/root/.ipython \
	/root/.ipython/profile_default \
	/root/.vscode-server \
	/root/.claude \
	/root/.config \
	/root/.config/code-server \
	/root/.cache \
	/root/workspace || true

# Notebook Intelligence defaults
if [ ! -f /root/.jupyter/nbi/config.json ]; then
	echo '{}' > /root/.jupyter/nbi/config.json || true
fi
if [ ! -f /root/.jupyter/nbi/mcp.json ]; then
	echo '{"mcpServers":{}}' > /root/.jupyter/nbi/mcp.json || true
fi

# Ensure NBI dir + files are group-writable and setgid
chmod -R 775 /root/.jupyter/nbi 2>/dev/null || true
chgrp -R root /root/.jupyter/nbi 2>/dev/null || true
find /root/.jupyter/nbi -type d -exec chmod g+s {} \; 2>/dev/null || true

# code-server config
cat > /root/.config/code-server/config.yaml <<EOF
auth: none
bind-addr: 127.0.0.1:0
EOF

# Fix permissions
chmod -R 775 /root/.jupyter /root/.local /root/.config /root/.cache /root/workspace 2>/dev/null || true
chgrp -R root /root/.local /root/.config /root/.cache /root/workspace 2>/dev/null || true
find /root/.local /root/.config /root/.cache /root/.jupyter -type d -exec chmod g+s {} \; 2>/dev/null || true

# Generate single-user Jupyter server config
cat > /root/.jupyter/jupyter_server_config.py <<PYEOF
import os
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.open_browser = False
c.ServerApp.allow_root = True
c.ServerApp.allow_remote_access = True
c.ServerApp.root_dir = '/root'
c.ServerApp.terminado_settings = {"shell_command": ["/bin/bash"]}
c.ContentsManager.allow_hidden = True
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ResourceUseDisplay.track_disk_usage = True
c.ResourceUseDisplay.track_cpu_percent = True
c.MappingKernelManager.cull_idle_timeout = 7200
c.MappingKernelManager.cull_interval = 300
c.MappingKernelManager.cull_connected = True
c.MappingKernelManager.cull_busy = False
c.ServerApp.jpserver_extensions = {"notebook_intelligence": True}
c.NotebookNotary.enabled = False
PYEOF

# Background: fix permissions on files/dirs created with restricted permissions.
SHARE_DIRS=(
	/root/.local/share/jupyter
	/root/.local/share/code-server
	/root/.local/share/jupyterlab
	/root/.jupyter/nbi
	/root/.jupyter/lab
	/root/.ipython
	/root/.vscode-server
	/root/.claude
	/root/.cache
)
(while true; do
	find "${SHARE_DIRS[@]}" -type f -not -perm -020 -exec chmod g+rw {} \; 2>/dev/null || true
	find "${SHARE_DIRS[@]}" -type d -not -perm -020 -exec chmod g+rwx {} \; 2>/dev/null || true
	for f in /root/.claude.json /root/.gitconfig /root/.netrc; do
		[ -f "$f" ] && chmod 664 "$f" 2>/dev/null || true
	done
	sleep 3
done) &

# --- SSH compatibility with JupyterHub ---
if [ -f /etc/ssh/sshd_config ]; then
	log "Fixing SSH compatibility for JupyterHub (StrictModes)..."
	chmod 700 /root/.ssh 2>/dev/null || true
	chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

	if grep -q '^StrictModes' /etc/ssh/sshd_config 2>/dev/null; then
		sed -i 's/^StrictModes.*/StrictModes no/' /etc/ssh/sshd_config || true
	else
		echo 'StrictModes no' >> /etc/ssh/sshd_config || true
	fi

	for pidfile in /run/sshd.pid /var/run/sshd.pid; do
		if [ -r "$pidfile" ]; then
			kill -HUP "$(cat "$pidfile")" 2>/dev/null && log "sshd reloaded" && break
		fi
	done
fi

# Execute CMD from Dockerfile
log "Container initialization complete. Handing off to CMD..."
exec "$@"