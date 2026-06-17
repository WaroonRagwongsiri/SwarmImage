FROM ubuntu:24.04

# ---- Global Configuration ----
ENV PERSISTENT_DIR="/root"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ---- KKU Thai mirror, official archive as fallback ----
RUN sed -i 's|URIs: http://archive.ubuntu.com/ubuntu/|URIs: http://mirror.kku.ac.th/ubuntu/ http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

# ---- Persistence: redirect apt cache, keep .debs, auto-record manifest ----
RUN mkdir -p ${PERSISTENT_DIR}/apt-cache && \
	chown -R _apt:root ${PERSISTENT_DIR}/apt-cache && \
	printf "Dir::Cache::Archives \"${PERSISTENT_DIR}/apt-cache\";\n" > /etc/apt/apt.conf.d/01-persistent-cache && \
	printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/02-keep-debs && \
	printf "DPkg::Post-Invoke { \"apt-mark showmanual > ${PERSISTENT_DIR}/installed.manifest.new && mv ${PERSISTENT_DIR}/installed.manifest.new ${PERSISTENT_DIR}/installed.manifest || true\"; };\n" > /etc/apt/apt.conf.d/03-manifest-hook

# ---- Full system packages — VM-like experience ----
RUN apt-get update && apt-get install -y --no-install-recommends \
	iputils-ping iproute2 net-tools dnsutils traceroute nmap \
	wget curl vim nano htop tmux screen tree less build-essential \
	git git-lfs openssh-client jq zip rsync ffmpeg cmake sudo \
	ca-certificates gnupg locales procps unzip fonts-thai-tlwg file \
	&& locale-gen en_US.UTF-8 \
	&& rm -rf /var/lib/apt/lists/*

# ---- CUDA Toolkit 13.3 ----
WORKDIR /tmp
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
	&& dpkg -i cuda-keyring_1.1-1_all.deb \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends cuda-toolkit-13-3 \
	&& rm cuda-keyring_1.1-1_all.deb \
	&& rm -rf /var/lib/apt/lists/*
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# ---- UV & Python 3.13 ----
# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

# Set UV to use the dynamic persistent volume variable
ENV UV_PYTHON_INSTALL_DIR="${PERSISTENT_DIR}/uv/python"
ENV UV_CACHE_DIR="${PERSISTENT_DIR}/uv/cache"
ENV UV_TOOL_DIR="${PERSISTENT_DIR}/uv/tools"

# Pre-install Python 3.13 using uv so it's baked into the image
RUN uv python install 3.13

# ---- NVM & NodeJS ----
ENV NVM_DIR="/usr/local/nvm"
ENV NODE_VERSION="22"

RUN mkdir -p $NVM_DIR && \
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash && \
	. $NVM_DIR/nvm.sh && \
	nvm install $NODE_VERSION && \
	nvm alias default $NODE_VERSION && \
	nvm use default

ENV PATH="$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH"

# ---- Entrypoint & Daemon Setup ----
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Keep Swarm container alive
CMD ["sleep", "infinity"]