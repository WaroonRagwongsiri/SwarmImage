#!/bin/bash

export PATH="/opt/venv/bin:/usr/local/bin:$PATH"

# ── Create all shared directories upfront ──────────────────────
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
	/root/workspace

# Notebook Intelligence — create default config if not exists (shared across all users)
mkdir -p /root/.jupyter/nbi /root/.jupyter/nbi/rules
if [ ! -f /root/.jupyter/nbi/config.json ]; then
	echo '{}' > /root/.jupyter/nbi/config.json
fi
if [ ! -f /root/.jupyter/nbi/mcp.json ]; then
	echo '{"mcpServers":{}}' > /root/.jupyter/nbi/mcp.json
fi
# Ensure NBI dir + files are group-writable and setgid (so admin edits don't lock out other users)
chmod -R 775 /root/.jupyter/nbi 2>/dev/null
chgrp -R root /root/.jupyter/nbi 2>/dev/null
find /root/.jupyter/nbi -type d -exec chmod g+s {} \; 2>/dev/null

# code-server config — no password (JupyterHub already handles auth)
cat > /root/.config/code-server/config.yaml <<EOF
auth: none
bind-addr: 127.0.0.1:0
EOF

# Fix permissions — all JupyterHub users (group root) need write access
chmod -R 775 /root/.jupyter /root/.local /root/.config /root/.cache /root/workspace 2>/dev/null
chgrp -R root /root/.local /root/.config /root/.cache /root/workspace 2>/dev/null

# Set setgid bit on key dirs — new files/dirs auto-inherit root group
find /root/.local /root/.config /root/.cache /root/.jupyter -type d -exec chmod g+s {} \; 2>/dev/null

# Generate single-user Jupyter server config (used by spawned JupyterLab instances)
cat > /root/.jupyter/jupyter_server_config.py <<PYEOF
import os

c.ServerApp.ip = '0.0.0.0'
c.ServerApp.open_browser = False
c.ServerApp.allow_root = True
c.ServerApp.allow_remote_access = True
c.ServerApp.root_dir = '/root'
c.ServerApp.terminado_settings = {"shell_command": ["/bin/bash"]}
c.ContentsManager.allow_hidden = True

# No authentication — JupyterHub already handles user auth
c.ServerApp.token = ''
c.ServerApp.password = ''

# Resource usage display (memory + disk + CPU)
c.ResourceUseDisplay.track_disk_usage = True
c.ResourceUseDisplay.track_cpu_percent = True

# Cull idle kernels after 2 hours
c.MappingKernelManager.cull_idle_timeout = 7200
c.MappingKernelManager.cull_interval = 300
c.MappingKernelManager.cull_connected = True
c.MappingKernelManager.cull_busy = False

# Explicitly enable NBI server extension (ensures it loads for all users)
c.ServerApp.jpserver_extensions = {
	"notebook_intelligence": True,
}

# Disable notebook signature database — SQLite creates files with 0644 permissions,
# which breaks multi-user shared HOME (other users get "readonly database" error).
# Notebook trust is not critical in a shared JupyterHub environment.
c.NotebookNotary.enabled = False
PYEOF

# Background: fix permissions on files/dirs created with restricted permissions.
# Many tools (SQLite, NBI, code-server, IPython) create files as 0600/0644.
# This loop ensures everything stays group-writable so all JupyterHub users can access them.
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
	find "${SHARE_DIRS[@]}" \
		-type f -not -perm -020 -exec chmod g+rw {} \; 2>/dev/null
	find "${SHARE_DIRS[@]}" \
		-type d -not -perm -020 -exec chmod g+rwx {} \; 2>/dev/null
	# Dotfiles in /root that also need group-write (claude, gitconfig, etc.)
	for f in /root/.claude.json /root/.gitconfig /root/.netrc; do
		[ -f "$f" ] && chmod 664 "$f" 2>/dev/null
	done
	sleep 3
done) &

# --- SSH compatibility with JupyterHub ---
if [ -f /etc/ssh/sshd_config ]; then
	echo "Fixing SSH compatibility for JupyterHub (StrictModes)..."
	chmod 700 /root/.ssh 2>/dev/null
	chmod 600 /root/.ssh/authorized_keys 2>/dev/null

	if grep -q '^StrictModes' /etc/ssh/sshd_config 2>/dev/null; then
		sed -i 's/^StrictModes.*/StrictModes no/' /etc/ssh/sshd_config
	else
		echo 'StrictModes no' >> /etc/ssh/sshd_config
	fi

	# Reload sshd to apply the new config
	for pidfile in /run/sshd.pid /var/run/sshd.pid; do
		if [ -r "$pidfile" ]; then
			kill -HUP "$(cat "$pidfile")" 2>/dev/null && echo "sshd reloaded (PID file: $pidfile)" && break
		fi
	done
fi

# Start JupyterHub (it spawns JupyterLab per-user automatically)
HUB_PORT="${JUPYTERHUB_PORT:-8000}"
echo "Starting JupyterHub on port $HUB_PORT ..."
cd /root
exec /opt/venv/bin/jupyterhub -f /etc/jupyterhub/jupyterhub_config.py
