FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Add KKU Thai mirror with the official Ubuntu archive as a fallback
RUN sed -i 's|URIs: http://archive.ubuntu.com/ubuntu/|URIs: http://mirror.kku.ac.th/ubuntu/ http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

# Full system packages — VM-like experience
RUN apt-get update && apt-get install -y --no-install-recommends \
	iputils-ping \
	iproute2 \
	net-tools \
	dnsutils \
	traceroute \
	nmap \
	wget \
	curl \
	vim \
	nano \
	htop \
	tmux \
	screen \
	tree \
	less \
	build-essential \
	git \
	git-lfs \
	openssh-client \
	jq \
	zip \
	rsync \
	ffmpeg \
	cmake \
	sudo \
	ca-certificates \
	gnupg \
	locales \
	procps \
	unzip \
	fonts-thai-tlwg \
	&& locale-gen en_US.UTF-8 \
	&& rm -rf /var/lib/apt/lists/*

## uv install
# Pull uv binary directly
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_PYTHON_INSTALL_DIR=/opt/uv_python

RUN uv python install 3.11

ENV VIRTUAL_ENV=/opt/venv
RUN uv venv $VIRTUAL_ENV --python 3.11

## Library
# PyTorch (CUDA 13.0 — must install first to avoid conflicts)
RUN uv pip install --no-cache-dir \
	torch torchvision torchaudio \
	--index-url https://download.pytorch.org/whl/cu130

# TensorFlow (CUDA 13.0)
RUN uv pip install --no-cache-dir \
	tensorflow[and-cuda] \
	tf-keras

# Core data science
RUN uv pip install --no-cache-dir \
	numpy \
	pandas \
	matplotlib \
	scikit-learn \
	scipy \
	seaborn

# JupyterLab extensions — install BEFORE jupyterlab to prevent downgrade
RUN uv pip install --no-cache-dir \
	ipywidgets \
	jupyterlab-git \
	jupyterlab-code-formatter \
	jupyter-resource-usage \
	jupyterlab-favorites \
	jupyter-archive \
	'jupyter-server-proxy[standalone]' \
	black isort \
	&& jupyter labextension disable "@jupyterlab/filebrowser-extension:share-file" 2>/dev/null || true

# JupyterLab 4.x — install AFTER extensions with --reinstall to guarantee version
RUN uv pip install --no-cache-dir --reinstall \
	jupyterlab==4.2.7 \
	jupyter_server \
	notebook \
	ipykernel \
	&& /opt/venv/bin/python -c "import jupyterlab; print(f'JupyterLab {jupyterlab.__version__} OK')" \
	&& /opt/venv/bin/python -c "import ipykernel; print(f'ipykernel OK')" \
	&& /opt/venv/bin/jupyter --version

# AI/ML — Hugging Face
RUN uv pip install --no-cache-dir \
	transformers \
	datasets \
	accelerate \
	peft \
	bitsandbytes \
	tokenizers \
	huggingface_hub \
	safetensors

# AI/ML — Generative AI / LLM
RUN uv pip install --no-cache-dir \
	langchain \
	langchain-community \
	sentence-transformers \
	diffusers

# Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
	&& apt-get install -y --no-install-recommends nodejs \
	&& rm -rf /var/lib/apt/lists/*

RUN npm install -g configurable-http-proxy

# JupyterHub + FirstUseAuthenticator
RUN uv pip install --no-cache-dir \
	jupyterhub \
	jupyterhub-firstuseauthenticator \
	jupyterhub-idle-culler

# JupyterHub config
COPY jupyterhub_config.py /etc/jupyterhub/jupyterhub_config.py

# Make /root group-writable so JupyterHub users (group root) can read/write
RUN chmod 775 /root

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8000

ENV JUPYTERHUB_ADMIN=admin
ENV JUPYTERHUB_PORT=8000
ENV JUPYTERHUB_SHARE_ENABLED=true
ENV JUPYTERHUB_SHARE_SECRET=sharetoken

WORKDIR /root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]