# Stage 1: base
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Taipei

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install tzdata and clean up
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user with fixed UID/GID
ARG USERNAME=user
ARG UID=500
ARG GID=500
RUN groupadd --gid $GID $USERNAME \
    && useradd --uid $UID --gid $GID --create-home --shell /bin/bash $USERNAME \
    && usermod -aG sudo $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory and switch to non-root user
USER $USERNAME
WORKDIR /home/$USERNAME

# Default command
CMD ["/bin/bash"]

# Stage 2: common_pkg_provider
FROM base AS common_pkg_provider
USER root

RUN apt-get update && apt-get install -y \
    vim \
    git \
    curl \
    wget \
    ca-certificates \
    build-essential \
    python3 \
    python3-pip \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh && \
    /opt/conda/bin/conda clean -ya

# Add conda to PATH
ENV PATH=/opt/conda/bin:$PATH

# Stage 3: verilator_provider
FROM common_pkg_provider AS verilator_provider
USER root

# Install Verilator build dependencies
RUN apt-get update && apt-get install -y \
    git \
    make \
    g++ \
    autoconf \
    automake \
    flex \
    bison \
    libfl-dev \
    libtool \
    perl \
    libperl-dev \
    zlib1g-dev \
    help2man \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Clone and checkout Verilator source
RUN git clone https://github.com/verilator/verilator.git /tmp/verilator && \
    cd /tmp/verilator && \
    git checkout v5.024

# Configure Verilator
RUN cd /tmp/verilator && \
    autoconf && \
    ./configure

# Build and install Verilator
RUN cd /tmp/verilator && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/verilator

# Verify Verilator installation
RUN verilator --version

# Stage 4: systemc_provider
FROM verilator_provider AS systemc_provider
USER root

# Install SystemC build dependencies
RUN apt-get update && apt-get install -y \
    libtool \
    autoconf \
    automake \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory to /tmp and install SystemC
RUN cd /tmp && \
    wget https://github.com/accellera-official/systemc/archive/refs/tags/2.3.4.tar.gz -O systemc-2.3.4.tar.gz && \
    tar -xzf systemc-2.3.4.tar.gz && \
    cd systemc-2.3.4 && \
    autoreconf -i && \
    mkdir build && cd build && \
    ../configure --prefix=/opt/systemc && \
    make -j$(nproc) && make install && \
    rm -rf /tmp/systemc-2.3.4*

# Set environment variables for SystemC
ENV SYSTEMC_HOME=/opt/systemc
ENV PATH=$SYSTEMC_HOME/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/systemc/lib-linux
ENV SYSTEMC_CXXFLAGS=-I$SYSTEMC_HOME/include
ENV SYSTEMC_LDFLAGS="-L$SYSTEMC_HOME/lib-linux -lsystemc"

# Stage 5: last
FROM base AS last
USER root

# Install essential tools in the final stage
RUN apt-get update && apt-get install -y \
    vim \
    git \
    curl \
    wget \
    ca-certificates \
    build-essential \
    python3 \
    python3-pip \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy from common_pkg_provider with chown
COPY --from=common_pkg_provider --chown=user:user /opt/conda /opt/conda
ENV PATH=/opt/conda/bin:$PATH

COPY --from=common_pkg_provider /usr/bin/python3 /usr/bin/python3
COPY --from=common_pkg_provider --chown=user:user /usr/bin/pip3 /usr/bin/pip3
COPY --from=common_pkg_provider --chown=user:user /usr/bin/vim /usr/bin/vim
COPY --from=common_pkg_provider --chown=user:user /usr/bin/git /usr/bin/git
COPY --from=common_pkg_provider --chown=user:user /usr/bin/curl /usr/bin/curl
COPY --from=common_pkg_provider --chown=user:user /usr/bin/wget /usr/bin/wget
COPY --from=common_pkg_provider --chown=user:user /usr/bin/make /usr/bin/make
COPY --from=common_pkg_provider --chown=user:user /usr/bin/gcc /usr/bin/gcc
COPY --from=common_pkg_provider --chown=user:user /usr/bin/g++ /usr/bin/g++

# Copy from verilator_provider with chown
COPY --from=verilator_provider --chown=user:user /usr/local/bin/verilator /usr/local/bin/verilator
COPY --from=verilator_provider --chown=user:user /usr/local/share/verilator /usr/local/share/verilator

# Copy from systemc_provider with chown
COPY --from=systemc_provider --chown=user:user /opt/systemc /opt/systemc

# Set environment variables for SystemC
ENV SYSTEMC_HOME=/opt/systemc
ENV PATH=$SYSTEMC_HOME/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/systemc/lib-linux
ENV SYSTEMC_CXXFLAGS=-I$SYSTEMC_HOME/include
ENV SYSTEMC_LDFLAGS="-L$SYSTEMC_HOME/lib-linux -lsystemc"

# Set working directory and switch to non-root user
USER user
WORKDIR /home/user

# Default command
CMD ["/bin/bash"]