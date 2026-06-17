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
	git git-lfs openssh-client openssh-server jq zip rsync ffmpeg cmake sudo \
	ca-certificates gnupg locales procps unzip fonts-thai-tlwg file \
	&& locale-gen en_US.UTF-8 \
	&& rm -rf /var/lib/apt/lists/*

# ---- SSH Configuration (Port 2222) ----
# Create SSH run directory, change port to 2222, allow root login, and set default password to root:root
RUN mkdir -p /run/sshd && \
	sed -i 's/#Port 22/Port 2222/g' /etc/ssh/sshd_config && \
	sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config && \
	echo "root:root" | chpasswd
EXPOSE 2222

# ---- Entrypoint & Daemon Setup ----
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Keep Swarm container alive
CMD ["sleep", "infinity"]