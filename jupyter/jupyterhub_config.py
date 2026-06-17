import os
import subprocess
import sys

# Set umask 002 so all spawned processes create group-writable files
os.umask(0o002)

c = get_config()

# ── Share Token — auto-login for shared proxy links ──────────────
# Set JUPYTERHUB_SHARE_ENABLED=false to disable.
# Set JUPYTERHUB_SHARE_SECRET to change the token.
# Share URL: http://host:PORT/hub/share?token=SECRET&next=/user/test/proxy/5000
# Public proxy: http://host:PORT/hub/public-proxy/{username}/{port}/path?_token=SECRET
SHARE_ENABLED = os.environ.get('JUPYTERHUB_SHARE_ENABLED', 'true').lower() != 'false'
SHARE_SECRET = os.environ.get('JUPYTERHUB_SHARE_SECRET', 'sharetoken')

if SHARE_ENABLED and SHARE_SECRET:
	import urllib.parse
	import tornado.httpclient
	from firstuseauthenticator import FirstUseAuthenticator
	from jupyterhub.handlers import BaseHandler

	# ── Handler 1: Auto-login (browser) ──────────────────────────
	class ShareLoginHandler(BaseHandler):
		"""Auto-login via share token — no password needed."""
		async def get(self):
			token = self.get_argument('token', '')
			next_url = self.get_argument('next', '/')

			if token != SHARE_SECRET:
				self.redirect(self.get_login_url())
				return

			user = self.find_user('viewer')
			if user is None:
				user = self.user_from_username('viewer')
				self.db.add(user)
				self.db.commit()

			self.set_login_cookie(user)
			self.redirect(next_url)

	# ── Handler 2: Public reverse proxy (API / no login) ─────────
	class PublicProxyHandler(BaseHandler):
		"""Reverse proxy to localhost services — no login, just token.
		URL: /hub/public-proxy/{username}/{port}/path?token=SECRET
		Header: Authorization: token SECRET
		"""

		def set_default_headers(self):
			self.set_header('Access-Control-Allow-Origin', '*')
			self.set_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS')
			self.set_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')

		def _check_token(self):
			if not SHARE_SECRET:
				return False
			# Use _token to avoid conflict with app's own ?token param
			token = self.get_argument('_token', '')
			if token == SHARE_SECRET:
				return True
			auth = self.request.headers.get('Authorization', '')
			if auth.startswith('token ') and auth[6:] == SHARE_SECRET:
				return True
			return False

		async def _proxy(self, username, port, path=''):
			if not self._check_token():
				self.set_status(403)
				self.write('Forbidden')
				return

			port_num = int(port)
			hub_port = int(os.environ.get('JUPYTERHUB_PORT', '8000'))
			if port_num == hub_port or port_num == 22:
				self.set_status(403)
				self.write('Port not allowed')
				return

			path = path.lstrip('/') if path else ''
			url = f'http://127.0.0.1:{port_num}/{path}'

			# Forward query string (strip _token param, keep app's own params)
			if self.request.query:
				qs = urllib.parse.parse_qs(self.request.query)
				qs.pop('_token', None)
				clean_qs = urllib.parse.urlencode(qs, doseq=True)
				if clean_qs:
					url += f'?{clean_qs}'

			method = self.request.method
			headers = {}
			for key in ('Content-Type', 'Accept', 'Accept-Language',
						'X-Requested-With', 'Authorization',
						'Referer', 'Origin', 'Cache-Control',
						'Sec-Fetch-Mode', 'Sec-Fetch-Dest', 'Sec-Fetch-Site'):
				val = self.request.headers.get(key)
				if val:
					headers[key] = val

			# Tell the backend app that it's behind a proxy at its own root
			# This helps apps like Gradio/Streamlit generate correct self-referencing URLs
			headers['X-Forwarded-Host'] = '127.0.0.1'
			headers['X-Forwarded-Proto'] = 'http'
			headers['X-Forwarded-Port'] = str(port_num)
			headers['X-Forwarded-For'] = self.request.remote_ip

			body = self.request.body if method in ('POST', 'PUT', 'PATCH') else None

			try:
				client = tornado.httpclient.AsyncHTTPClient()
				response = await client.fetch(
					url,
					method=method,
					headers=headers,
					body=body,
					request_timeout=60,
					follow_redirects=False,
				)
				for key, value in response.headers.items():
					if key.lower() not in ('transfer-encoding', 'connection', 'content-length'):
						self.set_header(key, value)
				self.set_status(response.code)
				self.write(response.body)
			except tornado.httpclient.HTTPError as e:
				self.set_status(e.code)
				if e.response:
					for key, value in e.response.headers.items():
						if key.lower() not in ('transfer-encoding', 'connection', 'content-length'):
							self.set_header(key, value)
					self.write(e.response.body)
				else:
					self.write(str(e))
			except Exception as e:
				self.set_status(502)
				self.write(f'Proxy error: {e}')

		async def get(self, username, port, path=''):
			# Auto-redirect: add trailing slash so browser resolves relative paths correctly
			if not path:
				self.redirect(f'/hub/public-proxy/{username}/{port}/')
				return
			await self._proxy(username, port, path)

		async def post(self, username, port, path=''):
			await self._proxy(username, port, path)

		async def put(self, username, port, path=''):
			await self._proxy(username, port, path)

		async def delete(self, username, port, path=''):
			await self._proxy(username, port, path)

		async def patch(self, username, port, path=''):
			await self._proxy(username, port, path)

		async def options(self, username, port, path=''):
			self.set_status(204)
			self.finish()

	class ShareAuthenticator(FirstUseAuthenticator):
		def get_handlers(self, app):
			return super().get_handlers(app) + [
				('/share', ShareLoginHandler),
				(r'/public-proxy/([^/]+)/(\d+)(/.*)?', PublicProxyHandler),
			]

	c.JupyterHub.authenticator_class = ShareAuthenticator
	c.Authenticator.admin_users = {os.environ.get('JUPYTERHUB_ADMIN', 'admin')}

	# RBAC: viewer can access user servers (proxy) but NOT admin panel
	c.JupyterHub.load_roles = [
		{
			"name": "viewer-role",
			"description": "Can access user proxy endpoints, nothing else",
			"scopes": ["access:servers"],
			"users": ["viewer"],
		},
	]
else:
	# No share token → normal FirstUseAuthenticator
	c.JupyterHub.authenticator_class = 'firstuseauthenticator.FirstUseAuthenticator'
	c.Authenticator.admin_users = {os.environ.get('JUPYTERHUB_ADMIN', 'admin')}

c.FirstUseAuthenticator.create_users = False

# ── Spawner — shared filesystem, everyone runs via /root ─────────
def create_system_user(spawner):
	"""Create Linux user with HOME=/root (shared) so JupyterLab sees the same files."""
	username = spawner.user.name
	try:
		subprocess.check_call(['id', username])
	except subprocess.CalledProcessError:
		subprocess.check_call([
			'useradd',
			'-d', '/root',       # home = /root (shared)
			'-M',                # don't create home dir (already exists)
			'-s', '/bin/bash',
			'-g', 'root',        # primary group = root → can read/write /root
			username,
		])

	# Ensure code-server Material Icon Theme settings (shared for all users)
	cs_settings_dir = '/root/.local/share/code-server/User'
	os.makedirs(cs_settings_dir, exist_ok=True)
	cs_settings_path = os.path.join(cs_settings_dir, 'settings.json')
	with open(cs_settings_path, 'w') as f:
		f.write('{\n')
		f.write('  "workbench.iconTheme": "material-icon-theme",\n')
		f.write('  "material-icon-theme.activeIconPack": "angular",\n')
		f.write('  "material-icon-theme.enableLogging": false,\n')
		f.write('  "material-icon-theme.files.color": "#90a4ae",\n')
		f.write('  "material-icon-theme.folders.color": "#90a4ae",\n')
		f.write('  "material-icon-theme.folders.theme": "specific",\n')
		f.write('  "material-icon-theme.hidesExplorerArrows": false,\n')
		f.write('  "material-icon-theme.opacity": 1,\n')
		f.write('  "material-icon-theme.saturation": 1\n')
		f.write('}\n')
	os.chmod(cs_settings_path, 0o664)

	# Each user gets their own runtime dir under /tmp to avoid permission conflicts
	runtime_dir = f'/tmp/jupyter-runtime-{username}'
	os.makedirs(runtime_dir, exist_ok=True)
	spawner.environment['JUPYTER_RUNTIME_DIR'] = runtime_dir

c.Spawner.pre_spawn_hook = create_system_user
c.Spawner.default_url = '/lab'

# Pass env vars to spawned single-user servers
c.Spawner.environment = {
	'CODE_DISABLE_PASSWORD': os.environ.get('CODE_DISABLE_PASSWORD', 'true'),
	'PATH': '/opt/venv/bin:/usr/local/bin:/usr/bin:/bin',
	'HOME': '/root',
	'LANG': 'en_US.UTF-8',
	'LC_ALL': 'en_US.UTF-8',
}

# Increase spawn timeout (first launch can be slow)
c.Spawner.http_timeout = 120
c.Spawner.start_timeout = 120

# ── Network ──────────────────────────────────────────────────────
c.JupyterHub.ip = '0.0.0.0'
c.JupyterHub.port = int(os.environ.get('JUPYTERHUB_PORT', '8000'))

# ── Idle Culler Service (kills user servers idle > 2h) ────────────
c.JupyterHub.services = [{
	'name': 'idle-culler',
	'admin': True,
	'command': [
		sys.executable, '-m', 'jupyterhub_idle_culler',
		'--timeout=7200',
		'--cull-every=300',
	],
}]

# ── Misc ─────────────────────────────────────────────────────────
c.JupyterHub.internal_ssl = False
