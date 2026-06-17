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

# Cuda Toolkit 13.3
WORKDIR /tmp
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
	&& dpkg -i cuda-keyring_1.1-1_all.deb \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends cuda-toolkit-13-3 \
	&& rm cuda-keyring_1.1-1_all.deb \
	&& rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

WORKDIR /root
CMD ["bash"]